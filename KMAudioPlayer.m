//
//  AudioPlayer.m
//  PlayDemo
//
//  Created by 中电兴发 on 2021/9/1.
//

#import "KMAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <assert.h>
const uint32_t CONST_BUFFER_SIZE = 0x10000;
#define INPUT_BUS 1
#define OUTPUT_BUS 0
@implementation KMAudioPlayer
{
    AudioStreamBasicDescription _recordFormat;
    dispatch_queue_t taskQueue;
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    AudioComponentInstance componetInstance;//用来表示特定音频组件的实例
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initPlayer];
    }
    return self;
}
-(void)play{

    // 开始播放
      dispatch_async(taskQueue, ^{
          
              //每次设置一下状态，防止别的地方被修改或者出现其他情况
              [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback  error:nil];
              AudioOutputUnitStart(self->audioUnit);
          });

}
-(void)initPlayer{
   
    NSError *error = nil;
    OSStatus status = noErr;
    
    //设置初始化
     AVAudioSession *session = [AVAudioSession sharedInstance];
      //设置采样率
      [session setPreferredSampleRate:44100 error:&error];
      //设置类型
      [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers error:&error];
      //
      [session setActive:YES withOptions:kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation error:&error];
      [session setActive:YES error:&error];
      
      //创建一个线程
      taskQueue = dispatch_queue_create("com.mt.audioCapture", NULL);
    
    AudioComponentDescription audioDesc;
    audioDesc.componentType = kAudioUnitType_Output;//类型输出
    audioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags = 0;
    audioDesc.componentFlagsMask = 0;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioDesc);
    AudioComponentInstanceNew(inputComponent, &audioUnit);
    
    buffList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
    buffList->mNumberBuffers = 1;
    buffList->mBuffers[0].mNumberChannels = 1;
    buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
    buffList->mBuffers[0].mData = malloc(CONST_BUFFER_SIZE);
    
    UInt32 flag = 1;
    if (flag) {
    
        status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, OUTPUT_BUS, &flag, sizeof(flag));
        
    }
    if (status) {
        NSLog(@"AudioUnitSetProperty error with status:%d", status);
    }

    // format
      AudioStreamBasicDescription outputFormat;
      memset(&outputFormat, 0, sizeof(outputFormat));
      outputFormat.mSampleRate       = 8000; // 常用采样率
      outputFormat.mFormatID         = kAudioFormatLinearPCM; // PCM格式
      outputFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger; // 整形
      outputFormat.mFramesPerPacket  = 1; // 每帧只有1个packet
      outputFormat.mChannelsPerFrame = 1; // 声道数
      outputFormat.mBytesPerFrame    = 2; // 每帧只有2个byte 声道*位深*Packet数
      outputFormat.mBytesPerPacket   = 2; // 每个Packet只有2个byte
      outputFormat.mBitsPerChannel   = 16; // 位深
    

      status = AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    OUTPUT_BUS,
                                    &outputFormat,
                                    sizeof(outputFormat));
      if (status) {
          NSLog(@"AudioUnitSetProperty eror with status:%d", status);
      }
      
      
      // callback
      AURenderCallbackStruct playCallback;
      playCallback.inputProc = PlayCallback;
      playCallback.inputProcRefCon = (__bridge void *)self;
      AudioUnitSetProperty(audioUnit,
                           kAudioUnitProperty_SetRenderCallback,
                           kAudioUnitScope_Input,
                           OUTPUT_BUS,
                           &playCallback,
                           sizeof(playCallback));
      
      
      OSStatus result = AudioUnitInitialize(audioUnit);
      NSLog(@"result %d", result);
    
}
void checkStatus(OSStatus status) {
    if(status!=0)
        printf("Error: %d\n", (int)status);
}
static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList * __nullable    ioData) {
    
    
   
    KMAudioPlayer *player = (__bridge KMAudioPlayer *)inRefCon;


    
    if(player.mData){
        AudioBuffer inBuffer = ioData->mBuffers[0];
//        memcpy(inBuffer.mData,player.mData ,player.length);
        ioData->mBuffers[0].mDataByteSize = player.length;
        ioData->mBuffers[0].mData = player.mData;
        memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    }else{
        for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
               memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
           }
    }
    
//    for (int i = 0; i < ioData->mNumberBuffers; i++) {
//        AudioBuffer buffer = ioData->mBuffers[i];
//        UInt16 *frameBuffer = buffer.mData;
//        for (int j = 0; j < inNumberFrames; j++) {
//            frameBuffer[j] = 0;
//        }
//    }
    
//    ioData = player.bufferList;
    NSLog(@"out size: %d", ioData->mBuffers[0].mDataByteSize);

    return noErr;
}
              

- (void)stop {
    dispatch_async(taskQueue, ^{
        AudioOutputUnitStop(self->audioUnit);
    });
    if (buffList != NULL) {
        if (buffList->mBuffers[0].mData) {
            free(buffList->mBuffers[0].mData);
            buffList->mBuffers[0].mData = NULL;
        }
        free(buffList);
        buffList = NULL;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(onPlayToEnd:)]) {
        __strong typeof (KMAudioPlayer) *player = self;
        [self.delegate onPlayToEnd:player];
    }
    

}

- (void)dealloc {
    AudioOutputUnitStop(audioUnit);
    AudioUnitUninitialize(audioUnit);
    AudioComponentInstanceDispose(audioUnit);
    
    if (buffList != NULL) {
        free(buffList);
        buffList = NULL;
    }
}


- (void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
    char formatID[5];
    UInt32 mFormatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy (&mFormatID, formatID, 4);
    formatID[4] = '\0';
    printf("Sample Rate:         %10.0f\n",  asbd.mSampleRate);
    printf("Format ID:           %10s\n",    formatID);
    printf("Format Flags:        %10X\n",    (unsigned int)asbd.mFormatFlags);
    printf("Bytes per Packet:    %10d\n",    (unsigned int)asbd.mBytesPerPacket);
    printf("Frames per Packet:   %10d\n",    (unsigned int)asbd.mFramesPerPacket);
    printf("Bytes per Frame:     %10d\n",    (unsigned int)asbd.mBytesPerFrame);
    printf("Channels per Frame:  %10d\n",    (unsigned int)asbd.mChannelsPerFrame);
    printf("Bits per Channel:    %10d\n",    (unsigned int)asbd.mBitsPerChannel);
    printf("\n");
}
@end
