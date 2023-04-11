//
//  XBOpenGLView.h
//

#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <AVFoundation/AVSampleBufferDisplayLayer.h>

@interface XBOpenGLView : UIImageView

@property (nonatomic, assign) BOOL isFullYUVRange;
@property (nonatomic, assign) int imageWidth;
@property (nonatomic, assign) int imageHeight;

- (CVPixelBufferRef)yuvPixelBufferWithData:(const char *)buffer
                                         y:(unsigned char *)y
                                         u:(unsigned char *)u
                                         v:(unsigned char *)v
                                     width:(size_t)w
                                    heigth:(size_t)h;

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (UIImage *)glToUIImage;

@end
