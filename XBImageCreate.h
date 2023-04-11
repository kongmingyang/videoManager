//
//  XBImageCreate.h
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@class XBImageCreate;

@protocol ImageCreateDelegate <NSObject>

- (void)imageFromAVPicture:(UIImage *)image;

@end


@interface XBImageCreate : NSObject

+ (instancetype)sharedImageCreate;

//RGB 数据传入
- (void)imageFromAVPicture:(char*)data width:(int)width height:(int)height;
+ (UIImage *)imageForRGBA:(unsigned char *)rgba
                    width:(CGFloat)width
                   height:(CGFloat)height;
-(UIImage *) convertBitmapRGBA8ToUIImage:(unsigned char *) buffer withWidth:(int) width withHeight:(int) height;
@property (nonatomic, weak) id<ImageCreateDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
