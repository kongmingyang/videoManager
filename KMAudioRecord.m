//
//  KMAudioRecord.m
//  KeepWatch
//
//  Created by 中电兴发 on 2023/3/29.
//

#import "KMAudioRecord.h"
@interface KMAudioRecord()
{
 
  AudioStreamBasicDescription _recordFormat;
  dispatch_queue_t taskQueue;
  AudioComponentInstance componetInstance;//用来表示特定音频组件的实例
}
@end
@implementation KMAudioRecord
- (instancetype)init
{
  self = [super init];
  if (self) {
    //重置下
       memset(&_recordFormat, 0, sizeof(_recordFormat));
      
        AudioComponentDescription acd;
         acd.componentType = kAudioUnitType_Output;//类型输出
         //acd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;//回声消除
         acd.componentSubType = kAudioUnitSubType_RemoteIO;//
         acd.componentManufacturer = kAudioUnitManufacturer_Apple;//ios固定这么写，mac不同
         acd.componentFlags = 0;
         acd.componentFlagsMask = 0;
         //用来描述音频组件
         AudioComponent component = AudioComponentFindNext(NULL, &acd);
         OSStatus status = noErr;
         //创建实例
         status = AudioComponentInstanceNew(component, &componetInstance);
         
         UInt32 flagOne = 1;
         //打开IO，1 是麦克风，0 是扬声器
         AudioUnitSetProperty(componetInstance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flagOne, sizeof(flagOne));
 
     _recordFormat.mSampleRate = 8000; //采样率
     _recordFormat.mChannelsPerFrame = 1;//声道数
     _recordFormat.mFormatID = kAudioFormatLinearPCM;
     _recordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked ;
    _recordFormat.mBitsPerChannel = 16;
    _recordFormat.mBytesPerFrame = (_recordFormat.mBitsPerChannel / 8) * _recordFormat.mChannelsPerFrame;
    _recordFormat.mFramesPerPacket = 1;// 非压缩数据，固定填1
    _recordFormat.mBytesPerPacket = _recordFormat.mBytesPerFrame * _recordFormat.mFramesPerPacket;
      
      AURenderCallbackStruct cb;//采集回调
         cb.inputProcRefCon = (__bridge  void *)(self);
         cb.inputProc = handleInputBuffer;
         status = AudioUnitSetProperty(componetInstance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &_recordFormat, sizeof(_recordFormat));//设置流格式
         status = AudioUnitSetProperty(componetInstance, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));//设置回调
     
      //设置初始化
       AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *error;
        //设置采样率
        [session setPreferredSampleRate:44100 error:&error];
        //设置类型
        [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers error:&error];
        //
        [session setActive:YES withOptions:kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation error:&error];
        [session setActive:YES error:&error];
        
        //创建一个线程
        taskQueue = dispatch_queue_create("com.mt.audioCapture", NULL);
      
      

  }
  return self;
}

-(void)startRecording
{
  // 开始录音
    dispatch_async(taskQueue, ^{
            NSLog(@"开始录音");
            //每次设置一下状态，防止别的地方被修改或者出现其他情况
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers error:nil];
            AudioOutputUnitStart(self->componetInstance);
        });
}

static OSStatus handleInputBuffer(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    @autoreleasepool {
        KMAudioRecord *source = (__bridge KMAudioRecord *)inRefCon;
        
        if (!source) {
            return -1;
        }
        
        AudioBuffer buffer;
        buffer.mData = NULL;
        buffer.mDataByteSize = 0;
        buffer.mNumberChannels = 1;
        
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0] = buffer;
        
        static int64_t get_audio_base_timesss = 0;
        Float64 currentTime = CMTimeGetSeconds(CMClockMakeHostTimeFromSystemUnits(inTimeStamp->mHostTime));
        if (get_audio_base_timesss == 0) {
            get_audio_base_timesss = currentTime;
        }
        int64_t pts = (int64_t)((currentTime - get_audio_base_timesss) * 1000);
        
        ///获取数据
        OSStatus status = AudioUnitRender(source->componetInstance,
                                          ioActionFlags,
                                          inTimeStamp,
                                          inBusNumber,
                                          inNumberFrames,
                                          &bufferList);
        
        if ((NO)) {
            for (int i = 0; i < bufferList.mNumberBuffers; i++) {
                AudioBuffer ab = bufferList.mBuffers[i];
                memset(ab.mData, 0, ab.mDataByteSize);
            }
        }
        
        if (status == noErr) {
            //            //音频数据
//            bufferList.mBuffers[0].mData
            NSData *data = [NSData dataWithBytes:bufferList.mBuffers[0].mData length:bufferList.mBuffers[0].mDataByteSize];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"EYRecordNotifacation" object:@{@"data" : data}];
            
            //            //音频长度
//                  bufferList.mBuffers[0].mDataByteSize
            //            //pts
            //            pts
            //            //转为NSData
            //            [NSData dataWithBytes:bufferList.mBuffers[0].mData length:bufferList.mBuffers[0].mDataByteSize]
        }
        /*如果有分离左右声道需求的话
         //            NSData *data = [NSData dataWithBytes:buffers.mBuffers[0].mData length:buffers.mBuffers[0].mDataByteSize];
         //
         //               NSMutableData *leftData = [NSMutableData dataWithCapacity:0];
         //               NSMutableData *rightData = [NSMutableData dataWithCapacity:0];
         //            // 分离左右声道
         //             for (int i = 0; i < data.length; i+=4) {
         //                 [leftData appendData:[data subdataWithRange:NSMakeRange(i, 2)]];
         //                 [rightData appendData:[data subdataWithRange:NSMakeRange(i+2, 2)]];
         //             }
         */
        return noErr;
    }
}

-(void)stopRecording
{

    dispatch_async(taskQueue, ^{
          NSLog(@"停止录音");
          AudioOutputUnitStop(self->componetInstance);
      });
  NSLog(@"停止录音");
}

@end
