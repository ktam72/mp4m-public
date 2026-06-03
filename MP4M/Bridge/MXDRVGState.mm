//
//  MXDRVGState.mm
//  MXDRVGState の実装（シンプル版）
//

#import "MXDRVGState.h"

@implementation MXDRVGState

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初期値設定（元のグローバル変数の初期化に合わせる）
        strncpy(lastPDXFileName, "No PDX", sizeof(lastPDXFileName) - 1);
        lastPDXFileName[sizeof(lastPDXFileName) - 1] = '\0';
        pdxLoadError[0] = '\0';
        lastTitle[0] = '\0';
        _ymfmDebugHighResInterval = 60;

        // ミュート配列はゼロ初期化（@public インスタンス変数）
        memset(fmMutedTL, 0, sizeof(fmMutedTL));
        memset(pcmMutedVol, 0, sizeof(pcmMutedVol));
        memset(fmMuteState, 0, sizeof(fmMuteState));
        memset(pcmMuteState, 0, sizeof(pcmMuteState));
    }
    return self;
}

@end
