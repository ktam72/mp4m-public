//
//  MXDRVGChannelManager.h
//  MXDRVGBridge からチャンネル状態取得・ミュート制御を分離
//

#import <Foundation/Foundation.h>
#include "MP4M-Bridging-Header.h"

@interface MXDRVGChannelManager : NSObject

+ (void)getChannelStates:(MP4MChannelState *)states;
+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted;

@end
