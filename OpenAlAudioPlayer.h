//
//  OpenAlAudioPlayer.h
//  PlayDemo
//
//  Created by 中电兴发 on 2021/9/10.
//

#import <Foundation/Foundation.h>
#import <OpenAL/OpenAL.h>
NS_ASSUME_NONNULL_BEGIN

@interface OpenAlAudioPlayer : NSObject
@property(nonatomic,assign)int m_numprocressed;//队列中已经播放过的数量
@property(nonatomic,assign)int m_numqueued;//队列中缓冲队列数量
@property(nonatomic,assign)long long m_IsplayBufferSize;   //已经播放了多少个音频缓存数目
@property(nonatomic,assign) double m_oneframeduration;      //一帧音频数据持续时间(ms)
@property(nonatomic,assign)float m_volume; //当前音量volume取值范围(0~1)
@property(nonatomic,assign) int m_samplerate; //采样率
@property(nonatomic,assign) int m_bit; //样本值
@property(nonatomic,assign) int m_channel;                  //声道数
@property(nonatomic,assign) int m_datasize;                 //一帧音频数据量
@property(nonatomic,assign) double playRate;                //播放速率
+(id)sharePalyer;

/**
 *  播放
 *
 *  @param data       数据
 *  @param dataSize   长度
 *  @param samplerate 采样率
 *  @param channels   通道 1单声道 2 双声道
 *  @param bit        位数 一般是16
 */
-(void)openAudioFromQueue:(uint8_t *)data dataSize:(size_t)dataSize samplerate:(int)samplerate channels:(int)channels bit:(int)bit;

/**
 *  停止播放
 */
-(void)stopSound;
@end


NS_ASSUME_NONNULL_END
