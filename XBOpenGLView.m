//
//  XBOpenGLView.m
//

#import "XBOpenGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <GLKit/GLKit.h>

/*
 * 重要说明:
 *  1. 此为mstar、FFmpeg解码得到YUV后经过OpenGL绘制类。
 *  2. 以1920*1080 15fps 4M 解码HEVC为例，从接收YUV数据转换到pix到OpenGL绘制,参考耗时iPhone5c 13ms，iPhone6 11ms，iPhone6s 9ms。相比采用系统库转换绘制，性能获得较大提升。
 *  3. 在iPhone6s 以下机型视频仍然会出现卡顿延迟。mstar、FFmpeg仍需要优化到YUV的解码速度。
 *  4. iphone 6  iOS11.4.1  3Min 局域网解码平均测试结果。
        1080P 4M 25fps 57ms
        1080P 2M 25fps 46ms
        1080P 1M 25fps 42ms

        720P 4M 25fps 32ms
        720P 2M 25fps 27ms
        720P 1M 25fps 18ms  （延迟少）
 
        iphone X  iOS11.4   3Min 局域网解码平均测试结果。(基本无延迟)
        1080P 4M 25fps 10ms
        1080P 2M 25fps 9ms
        1080P 1M 25fps 9ms
 */

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
const GLfloat kColorConversion601FullRange[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};

typedef unsigned char BYTE;

typedef struct RGB24 {
    BYTE    rgbRed;       // 红色分量
    BYTE    rgbGreen;     // 绿色分量
    BYTE    rgbBlue;      // 蓝色分量
} RGB24;

@interface XBOpenGLView ()
{
    // The pixel dimensions of the CAEAGLLayer.
    GLint _backingWidth;
    GLint _backingHeight;
    
    EAGLContext *_context;
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;
    
    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;
    
    const GLfloat *_preferredConversion;
    
    CVPixelBufferRef pixelBuffer;
}

@property GLuint program;

- (void)setupBuffers;
- (void)cleanUpTextures;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation XBOpenGLView

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        self.contentScaleFactor = [[UIScreen mainScreen] scale];
        
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
                                          kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};
        
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context || ![EAGLContext setCurrentContext:_context] || ![self loadShaders]) {
            return nil;
        }
        
        _preferredConversion = kColorConversion709;
        
        [self setupGL];
    }
    return self;
}

# pragma mark - OpenGL setup

- (void)setupGL
{
    [EAGLContext setCurrentContext:_context];
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program);
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
}

#pragma mark - Utilities

- (void)setupBuffers
{
    glDisable(GL_DEPTH_TEST);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
    
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

- (void)dealloc
{
    [self cleanUpTextures];
    
    if(_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}

#pragma mark - OpenGLES drawing

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    CVReturn err;
    if (pixelBuffer != NULL) {
        int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
        int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        if (!_videoTextureCache) {
            NSLog(@"No video texture cache");
            return;
        }
        if ([EAGLContext currentContext] != _context) {
            [EAGLContext setCurrentContext:_context]; // 非常重要的一行代码
        }
        [self cleanUpTextures];
        
        /*
         Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
         */
        CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        
        if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            if (self.isFullYUVRange) {
                _preferredConversion = kColorConversion601FullRange;
            }
            else {
                _preferredConversion = kColorConversion601;
            }
        }
        else {
            _preferredConversion = kColorConversion709;
        }
        
        /*
         CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef.
         */
        
        /*
         Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
         */
        // 激活纹理单元
        glActiveTexture(GL_TEXTURE0);
        // 从buffer中读取数据并创建chromaTexture和lumaTexture 纹理。
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_LUMINANCE,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_LUMINANCE,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_lumaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        // 纹理绑定
        glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
        // 纹理过滤
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // UV-plane.
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_LUMINANCE_ALPHA,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_LUMINANCE_ALPHA,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        //        NSLog(@"id %d", CVOpenGLESTextureGetName(_chromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
        
        // Set the view port to the entire view.
        glViewport(0, 0, _backingWidth, _backingHeight);
    }
    
    glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Use shader program.
    glUseProgram(self.program);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    // Set up the quad vertices with respect to the orientation and aspect ratio of the video.
    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(_backingWidth, _backingHeight), self.layer.bounds);
    
    // Compute normalized quad coordinates to draw the frame into.
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/self.layer.bounds.size.width, vertexSamplingRect.size.height/self.layer.bounds.size.height);
    
    // Normalize the quad vertices.
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
    }
    else {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.width/cropScaleAmount.height;
    }
    
    /*
     The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
     Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively, covers the entire screen.
     */
    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
        normalizedSamplingSize.width, normalizedSamplingSize.height,
    };
    
    // 更新顶点数据
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    GLfloat quadTextureData[] =  { // 更新纹理数据
        0, 1,
        1, 1,
        0, 0,
        1, 0
    };
    
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    // 绘制
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    if ([EAGLContext currentContext] == _context) {
        [_context presentRenderbuffer:GL_RENDERBUFFER];
    }
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSURL *vertShaderURL, *fragShaderURL;
    
    
    self.program = glCreateProgram();
    
    // Create and compile the vertex shader.
    vertShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(self.program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(self.program, fragShader);
    
    // Bind attribute locations. This needs to be done prior to linking.
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    // Link the program.
    if (![self linkProgram:self.program]) {
        NSLog(@"Failed to link program: %d", self.program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
    GLint status;
    const GLchar *source;
    source = (GLchar *)[sourceString UTF8String];
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

static OSType KVideoPixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
- (CVPixelBufferRef)yuvPixelBufferWithData:(const char *)buffer
                                         y:(unsigned char *)y
                                         u:(unsigned char *)u
                                         v:(unsigned char *)v
                                     width:(size_t)w
                                    heigth:(size_t)h {
    //unsigned char* buffer = (unsigned char*) dataFrame.bytes;
    NSDictionary *pixelBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSDictionary dictionary],kCVPixelBufferOpenGLCompatibilityKey,
                                           nil];
    if (pixelBuffer == NULL) {
        CVPixelBufferCreate(NULL, w, h, KVideoPixelFormatType, (__bridge CFDictionaryRef)(pixelBufferAttributes), &pixelBuffer);
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    /*
     size_t d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
     const unsigned char* src = buffer;
     unsigned char* dst = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
     
     for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += d, src += w) {
     memcpy(dst, src, w);
     }
     
     d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
     dst = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
     h = h >> 1;
     for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += d, src += w) {
     memcpy(dst, src, w);
     }
     */
    
    //size_t d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    //const unsigned char* src = buffer;
    
    unsigned char* dst = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    
    memcpy(dst, y, w * h);
    
    //d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    dst = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    
    //unsigned char *u = buffer + w * h;
    //unsigned char *v = buffer + w * h + w * h / 4;
    for (int i = 0; i < w * h / 4; i++)
    {
        dst[i * 2] = u[i];
        dst[i * 2 + 1] = v[i];
    }
    
    /*
     dst = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2);
     memcpy(dst, buffer + w * h + w * h / 4, w * h / 4);
     */
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return pixelBuffer;
}

- (UIImage *)glToUIImage {
    int _imageWidth = SCREEN_WIDTH * 2;
    int _imageHeight = _imageWidth * 9.0f / 16.f;
    NSInteger myDataLength = _imageWidth * _imageHeight * 4;
    NSLog(@"gl image wid = %d, height = %d", _imageWidth, _imageHeight);
    // allocate array and read pixels into it.
    GLubyte *buffer = (GLubyte *) malloc(myDataLength);
    glReadPixels(0, 0, _imageWidth, _imageHeight, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    // gl renders "upside down" so swap top to bottom into new array.
    // there's gotta be a better way, but this works.
    GLubyte *buffer2 = (GLubyte *) malloc(myDataLength);
    for(int y = 0; y < _imageHeight; y++)
    {
        for(int x = 0; x <_imageWidth * 4; x++)
        {
            buffer2[(_imageHeight -1 - y) * _imageWidth * 4 + x] = buffer[y * 4 * _imageWidth + x];
        }
    }
    free(buffer);
    // make data provider with data.
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer2, myDataLength, NULL);
    
    // prep the ingredients
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * _imageWidth;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    
    // make the cgimage
    CGImageRef imageRef = CGImageCreate(_imageWidth, _imageHeight, bitsPerComponent, bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider, NULL, NO, renderingIntent);
    
    //CGImageRef imageRef = CGImageCreate(width, height, 8, 24, width*3, colorSpace, kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault);
    
    // then make the uiimage from that
    UIImage *myImage = [UIImage imageWithCGImage:imageRef];
    
    return myImage;
}

// YUV420P YUV转RGB
- (void)Yuv420p2Rgb24:(unsigned char *)yuvBuffer_in rgb:(unsigned char *)rgbBuffer_out w:(int)width h:(int)height
{
    /*
     unsigned char *yuv = malloc(w * h * 4);
     memcpy(yuv, y, w * h);
     memcpy(yuv + w * h, u, w * h / 4);
     memcpy(yuv + w * h + w * h / 4, v, w * h / 4);
     [self Yuv420p2Rgb24:yuv rgb:rgb w:w h:h];*/
    unsigned char *yuvBuffer = (unsigned char *)yuvBuffer_in;
    RGB24 *rgb24Buffer = (RGB24 *)rgbBuffer_out;
    for (int y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            int index = y * width + x;
            int indexY = index;
            int indexU = width * height + y / 2 * width / 2 + x / 2;
            int indexV = width * height + width * height / 4 + y / 2 * width / 2 + x / 2;
            
            unsigned char Y = yuvBuffer[indexY];
            unsigned char U = yuvBuffer[indexU];
            unsigned char V = yuvBuffer[indexV];
            
            RGB24 *rgbNode = &rgb24Buffer[index];
            rgbNode->rgbRed = Y + 1.402 * (V-128);
            rgbNode->rgbGreen = Y - 0.34413 * (U-128) - 0.71414*(V-128);
            rgbNode->rgbBlue = Y + 1.772*(U-128);
        }
    }
}
// YUV420P Y,U,V转RGB
- (void)YUV2RGB24:(unsigned char *)y u:(unsigned char *)u v:(unsigned char *)v w:(int)width h:(int)height rgb:(unsigned char *)rgb{
    unsigned char m_r;
    unsigned char m_g;
    unsigned char m_b;
    RGB24 *rgb24Buffer = (RGB24 *)rgb;
    
    for (int j = 0; j < height; j++)
    {
        for (int i = 0; i < width; i++)
        {
            int indexY = j * width + i;
            int indexUV = j/2 * width/2 + i/2;
            
            [self MSTARYUV2RGB:y[indexY] u:u[indexUV] v:v[indexUV] r:&m_r g:&m_g b:&m_b];
            
            RGB24 *rgbNode = &rgb24Buffer[indexY];
            rgbNode->rgbRed = m_r;
            rgbNode->rgbGreen = m_g;
            rgbNode->rgbBlue = m_b;
        }
    }
    /*
     for (i = 0; i < (m_w * m_h); i++, j++)
     {
     if ((i / m_w + 1) % 2 == 0 && (i % m_w) == 0)
     {
     i = i + m_w;
     }
     
     [self MSTARYUV2RGB:y[i] u:u[j / 2] v:v[j / 2] r:&m_r g:&m_g b:&m_b];
     
     rgb[3 * i + 0] = (unsigned char)m_r;
     rgb[3 * i + 1] = (unsigned char)m_g;
     rgb[3 * i + 2] = (unsigned char)m_b;
     }*/
}

- (void)MSTARYUV2RGB:(BYTE)Y u:(BYTE)U v:(BYTE)V r:(BYTE *)Red g:(BYTE *)Green b:(BYTE *)Blue{
    /*
     *Red   = ((Y << 8) + ((V << 8) + (V << 5) + (V << 2))) >> 8;
     *Green = ((Y << 8) - ((U << 6) + (U << 5) + (U << 2)) - ((V << 7) + (V << 4) + (V << 2) + V)) >> 8;
     *Blue = ((Y << 8) + (U << 9) + (U << 3)) >> 8;
     */
    *Red = Y + 1.402 * (V-128);
    *Green = Y - 0.34413*(U-128) - 0.71414 * (V - 128);
    *Blue = Y + 1.772*(U-128);
}


@end

