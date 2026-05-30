//
//  MXDRVGBridge.m
//  ObjC wrapper for MXDRVG + LZX (MDXPlayer-main から流用)
//

#import "MXDRVGBridge.h"
#import "MDXFileLoader.h"
#import "MXDRVGState.h"
#include "../Vendor/gamdx/jni/mxdrvg/mxdrvg.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

extern "C" {
void OPM_GetChannelStates(MP4MChannelState* states, int max_channels);
int MXDRVG_GetPCM8ChannelMode(int ch);
}

// グローバル状態（MXDRVGState に集約）
static MXDRVGState *g_state = nil;

// MXDRVG エンジンをリセット（初期化・開始）
static void resetMXDRVGEngine(int sampleRate) {
    // UserDefaults からエンジン種別を復元（初回起動時はデフォルト=ymfm）
    NSInteger engineType = [[NSUserDefaults standardUserDefaults] integerForKey:@"mp4m_opmEngine"];

    // 例外安全対策：初期化中に例外が起きてもアプリを落とさない
    try {
        MXDRVG_End();
        MXDRVG_SetOpmEngine((int)engineType);
        MXDRVG_Start(sampleRate, 0, 64 * 1024, 1024 * 1024);
        MXDRVG_TotalVolume(128);

        // 【一時停止中】A-2 強制リセット（KNA03.MDX 等で一部パートが発音されなくなる副作用確認のため）
        // 初回音色不良対策として有効だったが、他の曲に悪影響が出るため一旦無効化。
        if (engineType == 0) {
            // MXDRVG_ForceYmfmRelease();
            // fprintf(stderr, "[resetMXDRVGEngine] ForceReleaseAllChannels executed at engine start (ymfm)\n");
        }
    } catch (...) {
        #ifdef DEBUG
        fprintf(stderr, "[MXDRVGBridge] EXCEPTION in resetMXDRVGEngine! Engine may be in unstable state.\n");
        #endif
    }
}

@implementation MXDRVGBridge

+ (void)startWithSampleRate:(int)sampleRate {
    #ifdef DEBUG
    fprintf(stderr, "[MXDRVGBridge] startWithSampleRate: %d\n", sampleRate);
    #endif

    if (!g_state) {
        g_state = [[MXDRVGState alloc] init];
    }

    resetMXDRVGEngine(sampleRate);

    // ymfm詳細デバッグログの有効化（MP4M_YMFM_DEBUG=1）
    const char* env = getenv("MP4M_YMFM_DEBUG");
    g_state.ymfmDebugEnabled = (env && atoi(env) != 0);
    if (g_state.ymfmDebugEnabled) {
        // HIGHRES が指定されていれば高頻度（約50ms間隔）に切り替え
        const char* highResEnv = getenv("MP4M_YMFM_HIGHRES");
        g_state.ymfmDebugHighResInterval = (highResEnv && atoi(highResEnv) != 0) ? 6 : 60;

        fprintf(stderr, "[OPM_DEBUG] OPM詳細ログを有効化 (MP4M_YMFM_DEBUG=1, interval=%d frames)\n",
                g_state.ymfmDebugHighResInterval);
    }

    #ifdef DEBUG
    fprintf(stderr, "[MXDRVGBridge] MXDRVG_Start done\n");
    #endif
}

+ (void)end {
    MXDRVG_End();
    g_state.mdxData = nil;
    g_state.pdxData = nil;
    memset(g_state->lastPDXFileName, 0, sizeof(g_state->lastPDXFileName));
}

+ (nullable NSString *)pdxFileName {
    if (g_state->lastPDXFileName[0] == '\0') return nil;
    NSString *name = [NSString stringWithUTF8String:g_state->lastPDXFileName];
    // "No PDX" の変種（例: (No PDX)、(No PDX).pdx など）を検出して統一
    if ([name.lowercaseString containsString:@"no pdx"]) {
        return @"No PDX";
    }
    return name;
}

+ (nullable NSString *)pdxLoadError {
    if (g_state->pdxLoadError[0] == '\0') return nil;
    return [NSString stringWithUTF8String:g_state->pdxLoadError];
}

+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath {
    // エンジン切り替え比較用に最後にロードしたパスを保持
    g_state.lastLoadedMDXPath = [mdxPath copy];

    // 最初に "No PDX" を設定（PDX未指定や読み込み失敗時に使用）
    strncpy(g_state->lastPDXFileName, "No PDX", sizeof(g_state->lastPDXFileName) - 1);
    g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
    #ifdef DEBUG
    fprintf(stderr, "[loadMDXFile] Loading: %s\n", [mdxPath UTF8String]);
    #endif
    NSData* fileData = [NSData dataWithContentsOfFile:mdxPath];
    if (!fileData) {
        #ifdef DEBUG
        fprintf(stderr, "[loadMDXFile] FAILED to load file\n");
        #endif
        return nil;
    }
    #ifdef DEBUG
    fprintf(stderr, "[loadMDXFile] Loaded file, size: %lu\n", (unsigned long)fileData.length);
    #endif

    // ファイルサイズチェック（INT_MAX および実用上限）
    #define MAX_MDX_FILE_SIZE (100 * 1024 * 1024)  // 100MB上限
    if (fileData.length == 0 || fileData.length > MAX_MDX_FILE_SIZE) {
        #ifdef DEBUG
        fprintf(stderr, "[loadMDXFile] ERROR: File size invalid (0 or >100MB)\n");
        #endif
        return nil;
    }

    NSString* mdxDir = [mdxPath stringByDeletingLastPathComponent];
    NSData* pdxData = nil;

    // MDX 内部からPDXファイル名を抽出
    const unsigned char* ptr = (const unsigned char*)fileData.bytes;

    // 整数オーバーフロー対策：size_t で計算
    size_t titleEndPos;
    for (titleEndPos = 0; titleEndPos < fileData.length - 1; titleEndPos++) {
        if (ptr[titleEndPos] == 0x0d && ptr[titleEndPos + 1] == 0x0a) break;
    }

    if (titleEndPos < fileData.length) {
        // mdxBodyStartPos = titleEndPos + 2 のオーバーフロー検証
        if (titleEndPos > fileData.length - 2) {
            #ifdef DEBUG
            fprintf(stderr, "[loadMDXFile] ERROR: Integer overflow detected in MDX header parsing\n");
            #endif
            return nil;
        }

        size_t mdxBodyStartPos;
        for (mdxBodyStartPos = titleEndPos + 2; mdxBodyStartPos < fileData.length; mdxBodyStartPos++) {
            if (ptr[mdxBodyStartPos] == 0x1a) break;
        }

        if (mdxBodyStartPos < fileData.length) {
            // mdxBodyStartPos++ のオーバーフロー検証
            if (mdxBodyStartPos >= INT_MAX) {
                #ifdef DEBUG
                fprintf(stderr, "[loadMDXFile] ERROR: Integer overflow in mdxBodyStartPos increment\n");
                #endif
                return nil;
            }
            mdxBodyStartPos++;  // 0x1A をスキップ

            // PDX ファイル名を抽出（最大 255 バイト）
            #define MAX_PDX_NAME_LEN 255
            size_t pdxNameEnd = mdxBodyStartPos;
            size_t pdxNameMaxLen = fileData.length - mdxBodyStartPos;
            while (pdxNameEnd < fileData.length && ptr[pdxNameEnd] != 0 &&
                   (pdxNameEnd - mdxBodyStartPos) < MAX_PDX_NAME_LEN) {
                pdxNameEnd++;
            }

            if (pdxNameEnd > mdxBodyStartPos && ptr[pdxNameEnd] == 0) {
                NSString* pdxFileName = [[NSString alloc] initWithBytes:&ptr[mdxBodyStartPos]
                                                                   length:(pdxNameEnd - mdxBodyStartPos)
                                                                 encoding:NSShiftJISStringEncoding];
                // Shift-JIS デコード失敗時は UTF-8 か ASCII として試す
                if (!pdxFileName) {
                    pdxFileName = [[NSString alloc] initWithBytes:&ptr[mdxBodyStartPos]
                                                             length:(pdxNameEnd - mdxBodyStartPos)
                                                           encoding:NSUTF8StringEncoding];
                }
                if (!pdxFileName) {
                    pdxFileName = [[NSString alloc] initWithBytes:&ptr[mdxBodyStartPos]
                                                             length:(pdxNameEnd - mdxBodyStartPos)
                                                           encoding:NSASCIIStringEncoding];
                }

                if (pdxFileName) {
                    #ifdef DEBUG
                    fprintf(stderr, "[PDX] Found PDX filename in MDX header: %s\n", [pdxFileName UTF8String]);
                    #endif

                    // セキュリティチェック：パストラバーサル対策
                    if (![MDXFileLoader isValidPDXFileName:pdxFileName]) {
                        #ifdef DEBUG
                        fprintf(stderr, "[PDX] SECURITY ERROR: PDX filename contains invalid characters (path separators or directory traversal): %s\n", [pdxFileName UTF8String]);
                        #endif
                        strncpy(g_state->lastPDXFileName, "No PDX", sizeof(g_state->lastPDXFileName) - 1);
                        g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
                    } else {
                        // 大文字小文字を区別せずにPDXファイルを検索
                        NSString* pdxPath = [MDXFileLoader findPDXFile:pdxFileName inDirectory:mdxDir];
                        if (pdxPath) {
                            #ifdef DEBUG
                            fprintf(stderr, "[PDX] Trying to load PDX from: %s\n", [pdxPath UTF8String]);
                            #endif
                            pdxData = [NSData dataWithContentsOfFile:pdxPath];
                            if (pdxData) {
                                #ifdef DEBUG
                                fprintf(stderr, "[PDX] Successfully loaded PDX file, size: %lu\n", (unsigned long)pdxData.length);
                                #endif
                                // 成功：グローバル変数に PDX ファイル名を保存
                                strncpy(g_state->lastPDXFileName, [pdxFileName UTF8String], sizeof(g_state->lastPDXFileName) - 1);
                                g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
                            } else {
                                #ifdef DEBUG
                                fprintf(stderr, "[PDX] Failed to load PDX file\n");
                                #endif
                                // 失敗："No PDX" を設定
                                strncpy(g_state->lastPDXFileName, "No PDX", sizeof(g_state->lastPDXFileName) - 1);
                                g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
                            }
                        } else {
                            #ifdef DEBUG
                            fprintf(stderr, "[PDX] PDX file not found (case-insensitive search)\n");
                            #endif
                            // 失敗："No PDX" を設定
                            strncpy(g_state->lastPDXFileName, "No PDX", sizeof(g_state->lastPDXFileName) - 1);
                            g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
                        }
                    }
                } else {
                    // PDX 指定がない場合は "No PDX" を設定
                    strncpy(g_state->lastPDXFileName, "No PDX", sizeof(g_state->lastPDXFileName) - 1);
                    g_state->lastPDXFileName[sizeof(g_state->lastPDXFileName) - 1] = '\0';
                    fprintf(stderr, "[PDX] No PDX specified in MDX header\n");
                }
            }
        }
    }

    return [MXDRVGBridge loadMDXData:fileData pdxData:pdxData];
}

+ (nullable NSString *)loadMDXData:(NSData *)mdxData pdxData:(nullable NSData *)pdxData {
    if (!mdxData) return nil;

    // エラーフラグをリセット
    memset(g_state->pdxLoadError, 0, sizeof(g_state->pdxLoadError));

    const unsigned char* ptr = (const unsigned char*)mdxData.bytes;

    // タイトル終端を探す
    int titleEndPos;
    for (titleEndPos = 0; titleEndPos < (int)mdxData.length - 1; titleEndPos++) {
        if (ptr[titleEndPos] == 0x0d && ptr[titleEndPos + 1] == 0x0a) break;
    }
    if (titleEndPos >= (int)mdxData.length) return nil;
    
    // 0x1A を探す
    int mdxBodyStartPos;
    for (mdxBodyStartPos = titleEndPos + 2; mdxBodyStartPos < (int)mdxData.length; mdxBodyStartPos++) {
        if (ptr[mdxBodyStartPos] == 0x1a) break;
    }
    if (mdxBodyStartPos >= (int)mdxData.length) return nil;
    
    mdxBodyStartPos++;  // 0x1A をスキップ
    
    // PDX ファイル名をスキップ
    int pdxNameStart = mdxBodyStartPos;
    while (mdxBodyStartPos < (int)mdxData.length && ptr[mdxBodyStartPos] != 0) {
        mdxBodyStartPos++;
    }
    mdxBodyStartPos++;  // ゼロ終端をスキップ
    
    // MDX 本体を LZX 展開
    NSData* mdxBody = [mdxData subdataWithRange:NSMakeRange(mdxBodyStartPos, mdxData.length - mdxBodyStartPos)];
    NSData* decompressed = [MDXFileLoader decompressIfLZX:mdxBody];
    if (!decompressed) return nil;
    
    // PDX 処理（PDX ロード失敗時のエラー検出）
    NSData* pdxDecompressed = nil;
    BOOL pdxLoadFailed = NO;
    if (pdxData) {
#ifdef DEBUG
        fprintf(stderr, "[PDX] Loading PDX data, original size: %lu bytes\n", (unsigned long)pdxData.length);
#endif
        pdxDecompressed = [MDXFileLoader decompressIfLZX:pdxData];
        if (pdxDecompressed) {
#ifdef DEBUG
            fprintf(stderr, "[PDX] PDX decompressed successfully, size: %lu bytes\n", (unsigned long)pdxDecompressed.length);
#endif
            // PDX デコンプレス成功
            g_state.hasPDX = 1;
        } else {
#ifdef DEBUG
            fprintf(stderr, "[PDX] PDX decompression failed, marking as error\n");
#endif
            // PDX デコンプレス失敗 → エラーメッセージを設定
            strncpy(g_state->pdxLoadError, "PDX decompression failed: file is corrupt", sizeof(g_state->pdxLoadError) - 1);
            g_state->pdxLoadError[sizeof(g_state->pdxLoadError) - 1] = '\0';
            pdxData = nil;
            g_state.hasPDX = 0;
            pdxLoadFailed = YES;
        }
    } else {
#ifdef DEBUG
        fprintf(stderr, "[PDX] No PDX data provided\n");
#endif
        g_state.hasPDX = 0;
    }

    // ヘッダー付与
    NSData* mdxWrapped = [MDXFileLoader wrapMDX:decompressed pdxData:pdxDecompressed];
    NSData* pdxWrapped = pdxDecompressed ? [MDXFileLoader wrapPDX:pdxDecompressed] : nil;

    // グローバル変数に保存（ARC が自動管理）
    g_state.mdxData = mdxWrapped;
    g_state.pdxData = pdxWrapped;

    // PDX ロード失敗時は、MXDRVG エンジンをリセットして MDX のみ登録
    if (pdxLoadFailed) {
#ifdef DEBUG
        fprintf(stderr, "[PDX] PDX load failed: resetting MXDRVG engine and reloading MDX only\n");
#endif
        resetMXDRVGEngine(44100);
    }

    // MDX/PDX データをエンジンに登録
    MXDRVG_SetData(
        (void*)g_state.mdxData.bytes, (unsigned long)g_state.mdxData.length,
        g_state.pdxData ? (void*)g_state.pdxData.bytes : NULL,
        g_state.pdxData ? (unsigned long)g_state.pdxData.length : 0
    );

    // タイトル抽出
    NSString* title = [MDXFileLoader titleFromData:mdxData];
    return title;
}

+ (void)playWithLoopCount:(int)loopCount {
    if (!g_state.mdxData) return;

    // PDX ロード失敗時は再生を実行しない
    if (g_state->pdxLoadError[0] != '\0') {
#ifdef DEBUG
        fprintf(stderr, "[playWithLoopCount] PDX load error detected, aborting playback\n");
#endif
        return;
    }

    // 総再生時間計測（内部状態を曲終端まで進めるため、直後に SetData で再初期化が必要）
    g_state.totalPlayTimeMs = MXDRVG_MeasurePlayTime(loopCount, 0);

    // MeasurePlayTime でシーケンスが終端まで進んだため SetData で冒頭へリセット
    MXDRVG_SetData(
        (void*)g_state.mdxData.bytes, (unsigned long)g_state.mdxData.length,
        g_state.pdxData ? (void*)g_state.pdxData.bytes : NULL,
        g_state.pdxData ? (unsigned long)g_state.pdxData.length : 0
    );

    // 【一時停止中】A-2 強制リセット（KNA03.MDX 等で一部パートが発音されなくなる副作用確認のため）
    // 初回音色不良対策として有効だったが、他の曲に悪影響が出るため一旦無効化。
    NSInteger currentEngine = [[NSUserDefaults standardUserDefaults] integerForKey:@"mp4m_opmEngine"];
    if (currentEngine == 0) {
        // MXDRVG_ForceYmfmRelease();
#ifdef DEBUG
        // fprintf(stderr, "[playWithLoopCount] ForceReleaseAllChannels executed after SetData (ymfm)\n");
#endif

        // デバッグ用：SetData直後の初期状態を高密度でダンプ（KNA03などの曲頭パーカッション問題調査用）
        // ymfm / fmgen 両方で同じ条件で出力して比較できるようにする
        if (g_state.ymfmDebugEnabled) {
            const char* initTag = (currentEngine == 0) ? "YMFM_CH_INIT" : "FMGEN_CH_INIT";
            const char* engineName = (currentEngine == 0) ? "ymfm" : "fmgen";
            fprintf(stderr, "[%s] === Initial state burst right after SetData (%s) ===\n", initTag, engineName);
            MP4MChannelState initStates[8];
            for (int burst = 0; burst < 12; ++burst) {
                memset(initStates, 0, sizeof(initStates));
                OPM_GetChannelStates(initStates, 8);
                fprintf(stderr, "[%s] ", initTag);
                for (int i = 0; i < 8; i++) {
                    fprintf(stderr, "CH%d:%s(kc=%02X,vol=%02X) ",
                            i+1,
                            initStates[i].keyOn ? "ON " : "OFF",
                            initStates[i].keyCode,
                            initStates[i].volume);
                }
                fprintf(stderr, "\n");
            }
            fprintf(stderr, "[%s] === End of initial burst ===\n", initTag);
        }
    }

    MXDRVG_PlayAt(0, loopCount, 1);
}

+ (void)stop {
    MXDRVG_Stop();
}

+ (void)pause {
    MXDRVG_Pause();
}

+ (void)resume {
    MXDRVG_Cont();
}

+ (BOOL)isTerminated {
    return MXDRVG_GetTerminated() ? YES : NO;
}

+ (int)currentPlayTimeMs {
    ULONG t = MXDRVG_GetPlayAt();
    return (int)t;
}

+ (int)totalPlayTimeMs {
    return g_state.totalPlayTimeMs;
}

+ (int)getPCM:(int16_t *)buf frameCount:(int)frameCount {
    // PDX ロード失敗時はサイレンスを返す
    if (g_state->pdxLoadError[0] != '\0') {
        memset(buf, 0, frameCount * sizeof(int16_t));
        return frameCount;
    }

    if (frameCount > 1024) frameCount = 1024;

    // 例外安全対策：C++ 側で例外が投げられてもオーディオスレッドを落とさない
    try {
        return MXDRVG_GetPCM(buf, frameCount);
    } catch (...) {
        #ifdef DEBUG
        fprintf(stderr, "[MXDRVGBridge] EXCEPTION in MXDRVG_GetPCM! Returning silence.\n");
        #endif
        memset(buf, 0, frameCount * sizeof(int16_t));
        return frameCount;
    }
}

+ (void)getChannelStates:(MP4MChannelState *)states {
    if (!states) return;
    memset(states, 0, sizeof(MP4MChannelState) * 16);

    // 例外安全対策：C++ 側（特に OPM_GetChannelStates / GetWork）で例外が起きてもクラッシュさせない
    try {
        // Get OPM channel states (FM 8ch)
        MP4MChannelState opmStates[8];
        memset(opmStates, 0, sizeof(opmStates));

        // Get PCM8 channel states (channels 8-15) from MXDRVG work area
        MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
        MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
        MXDRVG_WORK_GLOBAL* globalWork = (MXDRVG_WORK_GLOBAL*)MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL);

        OPM_GetChannelStates(opmStates, 8);

    // OPMチャンネル状態の詳細ログ出力（MP4M_YMFM_DEBUG=1時のみ）
    // ymfm / fmgen 両方で同じフォーマットで出力して比較しやすくする
    if (g_state.ymfmDebugEnabled) {
        g_state.ymfmDebugFrameCount++;
        if (g_state.ymfmDebugFrameCount % g_state.ymfmDebugHighResInterval == 0) {
            NSInteger engineType = [[NSUserDefaults standardUserDefaults] integerForKey:@"mp4m_opmEngine"];
            const char* tag = (engineType == 0) ? "[YMFM_CH]" : "[FMGEN_CH]";
            fprintf(stderr, "%s ", tag);
            for (int i = 0; i < 8; i++) {
                fprintf(stderr, "CH%d:%s(kc=%02X,vol=%02X) ",
                        i+1,
                        opmStates[i].keyOn ? "ON " : "OFF",
                        opmStates[i].keyCode,
                        opmStates[i].volume);
            }
            fprintf(stderr, "\n");
        }
    }

    // Convert FM channels (0-7)
    for (int i = 0; i < 8; i++) {
        states[i].keyCode = opmStates[i].keyCode;
        states[i].velocity = opmStates[i].velocity;
        states[i].keyOn = opmStates[i].keyOn;
        states[i].volume = opmStates[i].volume;
        states[i].bend = opmStates[i].bend;
        states[i].pan = opmStates[i].pan;
        states[i].keyOffset = opmStates[i].keyOffset;
        states[i].active = opmStates[i].active;
    }

    if (pcmCh) {
        // チャンネルマスクから有効な PCM チャンネル数を判定
        // L001e1a のビット 8-15 が PCM チャンネルに対応
        // bit 8: PCM1, bit 9: PCM2, ..., bit 15: PCM8
        uint16_t channelMask = globalWork ? globalWork->L001e1a : 0;

        for (int i = 0; i < 8; i++) {
            // 配列インデックス i がそのまま PCM1-8ch に対応
            // i=0 → PDX1ch (ch9), i=1 → PDX2ch (ch10), ..., i=7 → PDX8ch (ch16)
            int chIdx = 8 + i;  // Map array index directly to display positions
            int pcmBit = 8 + i;  // PCM channel bit position (bit 8-15)

            // チャンネルマスクでこの PCM チャンネルが有効か確認
            int isChannelEnabled = (channelMask & (1 << pcmBit)) ? 1 : 0;

            uint8_t flags = pcmCh[i].S0016;
            uint8_t keyOn = (flags >> 3) & 1;  // bit3 = keyon

            // PCM チャンネルが使用可能か判定
            UBYTE volatile* S0000 = pcmCh[i].S0000;  // Ptr フィールド
            uint8_t vol = pcmCh[i].S0022;  // volume
            uint8_t len = pcmCh[i].S001a;  // len

            // 実際に割り当て済みか判定：S0000 ポインタが有効（非ゼロ）
            // S0000 はサンプルデータへのポインタ。ゼロなら割り当てなし
            uint8_t isPlaying = (S0000 != NULL && S0000 != 0) ? 1 : 0;

            if (!isChannelEnabled || !g_state.hasPDX) {
                // このチャンネルはマスクで無効化されている、または PDX がない
                states[chIdx].keyOn = 0;
                states[chIdx].active = 0;
                states[chIdx].volume = 0;
                states[chIdx].velocity = 0;
                continue;
            }

            states[chIdx].keyOn = isPlaying;
            states[chIdx].active = isPlaying;

            // note+D is UWORD, lower bits = note
            uint16_t noteD = pcmCh[i].S0012;
            states[chIdx].keyCode = noteD & 0x7F;
            states[chIdx].keyOffset = 0;

            // PCM パン：PCM8::GetChannelMode() から取得
            // Mode の下位2ビット: bit0=Left, bit1=Right
            // 0b00: Center, 0b01: Left, 0b10: Right, 0b11: Stereo
            int pcm_mode = MXDRVG_GetPCM8ChannelMode(i);
            uint8_t pan_bits = pcm_mode & 0x03;
            if (pan_bits == 0x01) {
                states[chIdx].pan = 0;  // L（左）
            } else if (pan_bits == 0x02) {
                states[chIdx].pan = 2;  // R（右）
            } else if (pan_bits == 0x03) {
                states[chIdx].pan = 3;  // S（ステレオ）
            } else {
                states[chIdx].pan = 1;  // C（中央）
            }

            // Volume: 実際に再生中のときは 100、オフのときは 0
            states[chIdx].volume = isPlaying ? 127 : 0;
            // Spectrum analyzer用：再生中に基づいた固定値を使用（スケール変更を防ぐ）
            states[chIdx].velocity = isPlaying ? 100 : 0;
        }
    }
    } catch (...) {
        #ifdef DEBUG
        fprintf(stderr, "[MXDRVGBridge] EXCEPTION in getChannelStates! Returning empty state.\n");
        #endif
        // すでに memset でゼロクリア済みなので何もしない
    }
}

+ (void)setOpmEngine:(int)type {
    if (type == MXDRVG_GetOpmEngine()) return;

    NSString *fromName = [self opmEngineName];
    int currentTime = [self currentPlayTimeMs];

    // 切り替え前の状態を明確にログ出力（比較用）
    fprintf(stderr, "\n[ENGINE SWITCH] ========== ENGINE SWITCH ==========\n");
    fprintf(stderr, "[ENGINE SWITCH] From: %s → To: %s\n",
            [fromName UTF8String],
            (type == 0) ? "ymfm" : "fmgen");
    fprintf(stderr, "[ENGINE SWITCH] At currentTimeMs: %d\n", currentTime);
    fprintf(stderr, "[ENGINE SWITCH] ====================================\n\n");

    // 例外安全対策付きエンジン切り替え
    try {
        // 再生中にエンジンを切り替えるとスレッド競合のリスクがあるため停止する
        MXDRVG_Stop();
        MXDRVG_SetOpmEngine(type);
    } catch (...) {
        #ifdef DEBUG
        fprintf(stderr, "[MXDRVGBridge] EXCEPTION during engine switch! Attempting recovery.\n");
        #endif
        // 最低限エンジンを停止状態にしておく
        MXDRVG_Stop();
    }

    // 切り替え完了ログ
    fprintf(stderr, "[ENGINE SWITCH] Engine switched successfully. New engine: %s\n", [[self opmEngineName] UTF8String]);

    // 比較用途のため、同じ曲を自動で最初からロードし直す（位置0から）
    if (g_state.lastLoadedMDXPath) {
        fprintf(stderr, "[ENGINE SWITCH] Auto-reloading same file for comparison: %s\n", [g_state.lastLoadedMDXPath UTF8String]);
        [self loadMDXFile:g_state.lastLoadedMDXPath];
        // 自動で再生開始（loopCount=2固定で比較しやすくする）
        [self playWithLoopCount:2];
        fprintf(stderr, "[ENGINE SWITCH] Auto playback started after engine switch.\n");
    } else {
        fprintf(stderr, "[ENGINE SWITCH] No previous file loaded. Please manually load the same MDX to compare.\n");
    }
    fprintf(stderr, "[ENGINE SWITCH] ====================================\n\n");
}

+ (int)opmEngine {
    return MXDRVG_GetOpmEngine();
}

+ (NSString *)opmEngineName {
    return [NSString stringWithUTF8String:MXDRVG_GetOpmEngineName()];
}

+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted {
    if (ch < 0 || ch >= 16) return;

    if (ch < 8) {
        // FM チャンネル (0-7): YM2151 TL (Total Level) レジスタで制御
        MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
        if (!fmCh) return;

        if (isMuted) {
            if (!g_state->fmMuteState[ch]) {
                // ミュート開始：元の TL 値を保存して TL=127 に設定
                // FM ワークエリアの S001f (TL) フィールド
                uint8_t currentTL = fmCh[ch].S001f;
                g_state->fmMutedTL[ch] = currentTL;
                g_state->fmMuteState[ch] = 1;
                fmCh[ch].S001f = 127;  // 無音（最大減衰）
            }
        } else {
            if (g_state->fmMuteState[ch]) {
                // ミュート解除：保存した TL 値に復元
                fmCh[ch].S001f = g_state->fmMutedTL[ch];
                g_state->fmMuteState[ch] = 0;
            }
        }
    } else {
        // PCM チャンネル (8-15): volume で制御
        MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
        if (!pcmCh) return;

        int pcmIdx = ch - 8;
        if (pcmIdx < 0 || pcmIdx >= 8) return;

        if (isMuted) {
            if (!g_state->pcmMuteState[pcmIdx]) {
                // ミュート開始：元の volume を保存して 0 に設定
                uint8_t currentVol = pcmCh[pcmIdx].S0022;
                g_state->pcmMutedVol[pcmIdx] = currentVol;
                g_state->pcmMuteState[pcmIdx] = 1;
                pcmCh[pcmIdx].S0022 = 0;  // 無音
            }
        } else {
            if (g_state->pcmMuteState[pcmIdx]) {
                // ミュート解除：保存した volume に復元
                pcmCh[pcmIdx].S0022 = g_state->pcmMutedVol[pcmIdx];
                g_state->pcmMuteState[pcmIdx] = 0;
            }
        }
    }
}

@end
