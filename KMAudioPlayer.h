//
//  AudioPlayer.h
//  PlayDemo
//
//  Created by 中电兴发 on 2021/9/1.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
NS_ASSUME_NONNULL_BEGIN
@class KMAudioPlayer;
@protocol AudioPlayerDelegate <NSObject>

-(void)onPlayToEnd:(KMAudioPlayer*)player;

@end
typedef void (^AudioUnitPLayerInputBlock)(AudioBufferList *bufferList);
@interface KMAudioPlayer : NSObject
@property(nonatomic,copy) AudioUnitPLayerInputBlock audio_input;
@property(nonatomic,weak)id <AudioPlayerDelegate>delegate;
@property (nonatomic, assign) uint8_t *mData;
@property (nonatomic, assign) int length;
- (void)stop;
-(void)play;
@end

NS_ASSUME_NONNULL_END
