//
//  MXDRVGBridge.h
//  ObjC インターフェース
//

#import <Foundation/Foundation.h>
#include "MP4M-Bridging-Header.h"

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
+ (nullable NSString *)pdxFileName;
+ (nullable NSString *)pdxLoadError;
+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted;

+ (void)setOpmEngine:(int)type;
+ (int)opmEngine;
+ (NSString *)opmEngineName;

@end
