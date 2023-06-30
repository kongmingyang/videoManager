//
//  AudioPlayerManager.h
//  KeepWatch
//
//  Created by 中电兴发 on 2023/3/7.
//

#import <Foundation/Foundation.h>

#define QUEUE_BUFFER_SIZE 3//队列缓冲个数

#define MIN_SIZE_PER_FRAME 20480//每帧最小数据长度


@interface AudioPlayerManager : NSObject
- (instancetype)initWithSampleRate:(NSInteger)sampleRate
                          formatID:(AudioFormatID)formatID
                       formatFlags:(AudioFormatFlags)formatFlags
                  channelsPerFrame:(int)channelsPerFrame
                    bitsPerChannel:(int)bitsPerChannel
                   framesPerPacket:(int)framesPerPacket;

- (void)play:(NSData *)data;
- (void)stop;
-(void)resetPlay;
//释放播放器
- (void)releasePlayer;
@end


