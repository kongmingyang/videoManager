//
//  KFAudioConfig.h
//  KeepWatch
//
//  Created by 中电兴发 on 2023/4/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KFAudioConfig : NSObject
+ (instancetype)defaultConfig;

@property (nonatomic, assign) NSUInteger channels; // 声道数，default: 2。
@property (nonatomic, assign) NSUInteger sampleRate; // 采样率，default: 44100。
@property (nonatomic, assign) NSUInteger bitDepth; // 量化位深，default: 16。
@end

NS_ASSUME_NONNULL_END
