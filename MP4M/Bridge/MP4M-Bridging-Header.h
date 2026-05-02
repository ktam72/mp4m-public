//
//  MP4M-Bridging-Header.h
//  Swift Bridging Header
//

#ifndef MP4M_BRIDGING_HEADER_H
#define MP4M_BRIDGING_HEADER_H

#import <Foundation/Foundation.h>
#include <stdint.h>

// チャンネル状態（opm::ChannelState と一致させる）
typedef struct {
    uint8_t keyCode;
    uint8_t velocity;
    uint8_t keyOn;     // 0 = off, 1 = on
    uint8_t volume;
    int16_t bend;
    uint8_t pan;
    uint8_t keyOffset;
    uint8_t active;     // 追加：opm::ChannelState と一致
} MP4MChannelState;

// ObjC インターフェース
@interface MXDRVGBridge : NSObject

+ (void)startWithSampleRate:(int32_t)sampleRate;
+ (void)end;
+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath;
+ (nullable NSString *)loadMDXData:(NSData *)mdxData pdxData:(nullable NSData *)pdxData;
+ (void)playWithLoopCount:(int32_t)loopCount;
+ (void)stop;
+ (void)pause;
+ (void)resume;
+ (BOOL)isTerminated;
+ (int32_t)currentPlayTimeMs;
+ (int32_t)totalPlayTimeMs;
+ (int32_t)getPCM:(int16_t *)buf frameCount:(int32_t)frameCount;
+ (void)getChannelStates:(MP4MChannelState *)states;

@end

#endif // MP4M_BRIDGING_HEADER_H
