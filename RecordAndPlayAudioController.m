//
//  RecordAndPlayAudioController.m
//  BXAudioUnitPlayer
//
//  Created by 中电兴发 on 2023/6/30.
//  Copyright © 2023 baxiang. All rights reserved.
//

#import "RecordAndPlayAudioController.h"
#import "KFAudioCapture.h"
#import "KFAudioConfig.h"
#import "AudioPlayerManager.h"
@interface RecordAndPlayAudioController ()
{
    KFAudioCapture *audioCapture;
    //声音播放器
    AudioPlayerManager *audioPlayer;
}
@end

@implementation RecordAndPlayAudioController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}
-(void)playAudio{
    audioPlayer = [[AudioPlayerManager alloc] initWithSampleRate:8000 formatID:kAudioFormatLinearPCM formatFlags:kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked channelsPerFrame:1 bitsPerChannel:16 framesPerPacket:1];
    NSData *data = [NSData dataWithBytes:dataByte length:length];
    [audioPlayer play:data];
}
-(void)recordAudio{
    audioCapture = [[KFAudioCapture alloc]initWithConfig:[KFAudioConfig defaultConfig]];
    audioCapture.errorCallBack = ^(NSError * _Nonnull error) {
        NSLog(@"音频采集失败");
    };
    audioCapture.sampleBufferOutputCallBack = ^(CMSampleBufferRef  _Nonnull sampleBuffer) {
        if (sampleBuffer) {
                     // 1、获取 CMBlockBuffer，这里面封装着 PCM 数据。
                     CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                     size_t lengthAtOffsetOutput, totalLengthOutput;
                     char *dataPointer;
                     
                     // 2、从 CMBlockBuffer 中获取 PCM 数据存储到文件中。
                     CMBlockBufferGetDataPointer(blockBuffer, 0, &lengthAtOffsetOutput, &totalLengthOutput, &dataPointer);
            //发给后台的数据
            NSData *audioData =[NSData dataWithBytes:dataPointer length:totalLengthOutput];
            
            NSLog(@"数据-----%@----",audioData);
                
                 }
    };
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
