//
//  XBHEVCDecoder.h
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

//Image 回调
typedef void (^DecodeImgBlock)(UIImage *image);

//解码器失败回调
typedef void (^DecoderFaile)(BOOL faile);


@interface XBHEVCDecoder : NSObject

+ (instancetype)sharedDecoder;

@property (nonatomic, assign) BOOL synDecoder;

//初始化解码器
- (void)initDecoder:(DecodeImgBlock)block;

//解码器创建失败回调
-(void)decoderFaile:(DecoderFaile)block;

//H265 数据传入
-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize;

@end
