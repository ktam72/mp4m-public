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

// ObjC インターフェース (MXDRVGBridge.h で定義)
#import "MXDRVGBridge.h"

#endif // MP4M_BRIDGING_HEADER_H
