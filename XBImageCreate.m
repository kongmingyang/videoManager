//
//  XBImageCreate.m
//

#import "XBImageCreate.h"

@implementation XBImageCreate

+ (instancetype)sharedImageCreate
{
    return [[XBImageCreate alloc] init];
}

- (void)imageFromAVPicture:(char*)data width:(int)width height:(int)height{
   
    CFDataRef dataRef = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)data, width*height*4);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(dataRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       32,
                                       width*4,
                                       colorSpace,
                                       kCGBitmapByteOrderDefault,
                                       provider,
                                       NULL,
                                       YES,
                                       kCGRenderingIntentDefault);

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(dataRef);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *image = [UIImage imageWithCGImage:cgImage];
        [self.delegate imageFromAVPicture:image];
        CGImageRelease(cgImage);
    });

}

+(UIImage *)imageForRGBA:(unsigned char *)rgba
                    width:(CGFloat)width
                   height:(CGFloat)height {
    
    int bytes_per_pix = 4;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    CGContextRef newContext = CGBitmapContextCreate(rgba,
                                                    width, height, 8,
                                                    width * bytes_per_pix,
                                                    colorSpace, kCGImageAlphaNoneSkipLast);

    CGImageRef frame = CGBitmapContextCreateImage(newContext);
    
    UIImage *image = [UIImage imageWithCGImage:frame];
    
    CGImageRelease(frame);

    CGContextRelease(newContext);

    CGColorSpaceRelease(colorSpace);
    
    return image;
}
-(UIImage *) convertBitmapRGBA8ToUIImage:(unsigned char *) buffer withWidth:(int) width withHeight:(int) height {

size_t bufferLength = width * height * 4;

CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer, bufferLength, NULL);

size_t bitsPerComponent = 8;

size_t bitsPerPixel = 32;

size_t bytesPerRow = 4 * width;

CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();

if(colorSpaceRef == NULL) {

NSLog(@"Error allocating color space");

CGDataProviderRelease(provider);

return nil;

}

CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;

CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;

CGImageRef iref = CGImageCreate(width,

height,

bitsPerComponent,

bitsPerPixel,

bytesPerRow,

colorSpaceRef,

bitmapInfo,

provider,    // data provider

NULL,        // decode

YES,            // should interpolate

renderingIntent);

uint32_t* pixels = (uint32_t*)malloc(bufferLength);

if(pixels == NULL) {

NSLog(@"Error: Memory not allocated for bitmap");

CGDataProviderRelease(provider);

CGColorSpaceRelease(colorSpaceRef);

CGImageRelease(iref);

return nil;

}

CGContextRef context = CGBitmapContextCreate(pixels,width,height,bitsPerComponent,bytesPerRow,colorSpaceRef,bitmapInfo);

if(context == NULL) {

NSLog(@"Error context not created");

free(pixels);

}

UIImage *image = nil;

if(context) {

CGContextDrawImage(context, CGRectMake(0.0f, 0.0f, width, height), iref);

CGImageRef imageRef = CGBitmapContextCreateImage(context);

// Support both iPad 3.2 and iPhone 4 Retina displays with the correct scale

if([UIImage respondsToSelector:@selector(imageWithCGImage:scale:orientation:)]) {

float scale = [[UIScreen mainScreen] scale];

image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];

} else {

image = [UIImage imageWithCGImage:imageRef];

}

CGImageRelease(imageRef);

CGContextRelease(context);

}

CGColorSpaceRelease(colorSpaceRef);

CGImageRelease(iref);

CGDataProviderRelease(provider);

if(pixels) {

free(pixels);

}
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.delegate imageFromAVPicture:image];
       
    });
return image;

}

@end
