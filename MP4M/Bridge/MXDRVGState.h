//
//  MXDRVGState.h
//  MXDRVGBridge で使用するグローバル状態を1つに集約したシンプルなクラス
//
//  目的：14個に散らばっていた static グローバル変数を1箇所にまとめ、
//       将来のテスト容易性と責務明確化を図る（シンプル版）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MXDRVGState : NSObject
{
@public
    // C 文字列（元の strncpy / 配列アクセスを維持するため）
    char lastTitle[512];
    char lastPDXFileName[256];
    char pdxLoadError[256];

    // ミュート制御用 C 配列
    uint8_t fmMutedTL[8];
    uint8_t pcmMutedVol[8];
    int fmMuteState[8];
    int pcmMuteState[8];
}

// MARK: - ファイル / ロード状態
@property (nonatomic, strong, nullable) NSData *mdxData;
@property (nonatomic, strong, nullable) NSData *pdxData;
@property (nonatomic) int totalPlayTimeMs;
@property (nonatomic) int hasPDX;                               // BOOL 的に 0/1
@property (nonatomic, copy, nullable) NSString *lastLoadedMDXPath;

// MARK: - ymfm デバッグ用
@property (nonatomic) BOOL ymfmDebugEnabled;
@property (nonatomic) int ymfmDebugFrameCount;
@property (nonatomic) int ymfmDebugHighResInterval;             // 60=通常, 6=HIGHRES

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
