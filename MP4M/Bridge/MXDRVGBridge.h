//
//  MXDRVGBridge.h
//  ObjC インターフェース
//

#import <Foundation/Foundation.h>
#include "MP4M-Bridging-Header.h"

NS_ASSUME_NONNULL_BEGIN

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

/// MDX が要求した PDX が見つからなかったか
+ (BOOL)isPDXMissing;

/// 指定位置へシークする（先頭から高速演奏して到達させる）
/// @param ms シーク先（ミリ秒）
/// @param loopCount ループ回数
+ (void)seekToMs:(int)ms loopCount:(int)loopCount;
+ (nullable NSString *)pdxLoadError;
+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted;

+ (void)setOpmEngine:(int)type;
+ (int)opmEngine;
+ (NSString *)opmEngineName;

@end

NS_ASSUME_NONNULL_END
