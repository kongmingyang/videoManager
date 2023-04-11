//
//  KMRecord.h
//  PlayDemo
//
//  Created by 中电兴发 on 2021/9/16.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface KMRecord : NSObject
//开始录音
- (void)startRecording;

//停止录音
- (void)stopRecording;
@end


