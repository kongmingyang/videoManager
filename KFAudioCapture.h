//
//  KMRecordAudioManager.h
//  KeepWatch
//
//  Created by 中电兴发 on 2023/4/21.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "KFAudioConfig.h"
#import <mach/mach_time.h>
NS_ASSUME_NONNULL_BEGIN

@interface KFAudioCapture : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConfig:(KFAudioConfig *)config;

@property (nonatomic, strong, readonly) KFAudioConfig *config;
@property (nonatomic, copy) void (^sampleBufferOutputCallBack)(CMSampleBufferRef sample); // 音频采集数据回调。
@property (nonatomic, copy) void (^errorCallBack)(NSError *error); // 音频采集错误回调。
//开始录音
- (void)startRecording;

//停止录音
- (void)stopRecording;
@end

NS_ASSUME_NONNULL_END
