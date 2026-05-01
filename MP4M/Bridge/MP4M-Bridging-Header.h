//
//  MP4M-Bridging-Header.h
//  Swift Bridging Header
//

#ifndef MP4M_BRIDGING_HEADER_H
#define MP4M_BRIDGING_HEADER_H

#import <Foundation/Foundation.h>
#include <stdint.h>

// チャンネル状態
typedef struct {
    uint8_t keyCode;
    uint8_t velocity;
    uint8_t keyOn;
    uint8_t volume;
    int16_t bend;
    uint8_t pan;
    uint8_t keyOffset;
} MP4MChannelState;

// ObjC インターフェース
@interface MXDRVGBridge : NSObject

+ (void)startWithSampleRate:(int)sampleRate;
+ (void)end;
+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath;
+ (nullable NSString *)loadMDXData:(NSData *)mdxData pdxData:(nullable NSData *)pdxData;
+ (void)playWithLoopCount:(int)loopCount;
+ (void)stop;
+ (void)pause;
+ (void)resume;
+ (BOOL)isTerminated;
+ (int)currentPlayTimeMs;
+ (int)totalPlayTimeMs;
+ (int)getPCM:(int16_t *)buf frameCount:(int)frameCount;
+ (void)getChannelStates:(MP4MChannelState *)states;

@end

#endif // MP4M_BRIDGING_HEADER_H
