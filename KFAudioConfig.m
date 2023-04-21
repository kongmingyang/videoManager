//
//  KFAudioConfig.m
//  KeepWatch
//
//  Created by 中电兴发 on 2023/4/21.
//

#import "KFAudioConfig.h"

@implementation KFAudioConfig
+ (instancetype)defaultConfig {
    KFAudioConfig *config = [[self alloc] init];
    config.channels = 2;
    config.sampleRate = 8000;
    config.bitDepth = 16;
    
    return config;
}
@end
