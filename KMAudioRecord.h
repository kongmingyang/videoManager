//
//  KMAudioRecord.h
//  KeepWatch
//
//  Created by 中电兴发 on 2023/3/29.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
NS_ASSUME_NONNULL_BEGIN

@interface KMAudioRecord : NSObject
//开始录音
- (void)startRecording;

//停止录音
- (void)stopRecording;
@end

NS_ASSUME_NONNULL_END
