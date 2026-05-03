//
//  MXDRVGBridge.m
//  ObjC wrapper for MXDRVG + LZX (MDXPlayer-main から流用)
//

#import "MXDRVGBridge.h"
#include "../Vendor/gamdx/jni/mxdrvg/mxdrvg.h"
#include "../Vendor/lzx/lzx.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

extern "C" {
void OPM_GetChannelStates(MP4MChannelState* states, int max_channels);
int MXDRVG_GetPCM8ChannelMode(int ch);
}

// グローバル状態
static NSData* g_mdxData = nil;
static NSData* g_pdxData = nil;
static char g_lastTitle[512] = {0};
static char g_lastPDXFileName[256] = {0};
static int g_totalPlayTimeMs = 0;
static int g_hasPDX = 0;  // PDX が存在するかどうか
// チャンネルマュート用：元の出力レベルを保存
static uint8_t g_fmMutedTL[8] = {0};  // FM 各チャンネルのマュート時の元 TL 値
static uint8_t g_pcmMutedVol[8] = {0};  // PCM 各チャンネルのマュート時の元 volume 値
static int g_fmMuteState[8] = {0};  // FM マュート状態（0=非マュート、1=マュート中）
static int g_pcmMuteState[8] = {0};  // PCM マュート状態

// LZX 展開
static NSData* decompressIfLZX(NSData* data) {
    if (!data) return nil;
    
    const unsigned char* ptr = (const unsigned char*)data.bytes;
    int lzxlen = lzx::check(ptr, data.length);
    
    if (lzxlen <= 0) {
        // LZX 圧縮されていない
        return data;
    }
    
    unsigned char* lzxbuf = (unsigned char*)malloc(lzxlen);
    unsigned int retval = lzx::decompress(lzxbuf, lzxlen, ptr, data.length);
    
    if (retval == 0) {
        free(lzxbuf);
        return nil;  // デコード失敗
    }
    
    NSData* result = [NSData dataWithBytes:lzxbuf length:retval];
    free(lzxbuf);
    return result;
}

// MDX ヘッダー付与
static NSData* wrapMDX(NSData* body, NSData* pdx) {
    unsigned char mdxData[10];
    mdxData[0] = 0x00;
    mdxData[1] = 0x00;
    mdxData[2] = (unsigned char)(pdx ? 0 : 0xff);
    mdxData[3] = (unsigned char)(pdx ? 0 : 0xff);
    mdxData[4] = 0x00;
    mdxData[5] = 0x0a;
    mdxData[6] = 0x00;
    mdxData[7] = 0x08;
    mdxData[8] = 0x00;
    mdxData[9] = 0x00;
    
    NSMutableData* out = [NSMutableData dataWithBytes:mdxData length:10];
    [out appendData:body];
    return out;
}

// PDX ヘッダー付与
static NSData* wrapPDX(NSData* body) {
    unsigned char pdxData[10];
    pdxData[0] = 0x00;
    pdxData[1] = 0x00;
    pdxData[2] = 0x00;
    pdxData[3] = 0x00;
    pdxData[4] = 0x00;
    pdxData[5] = 0x0a;
    pdxData[6] = 0x00;
    pdxData[7] = 0x02;
    pdxData[8] = 0x00;
    pdxData[9] = 0x00;
    
    NSMutableData* out = [NSMutableData dataWithBytes:pdxData length:10];
    [out appendData:body];
    return out;
}

// Shift-JIS → UTF-8 簡易変換
static NSString* getTitleFromData(NSData* data) {
    if (!data) return nil;
    
    const unsigned char* ptr = (const unsigned char*)data.bytes;
    
    // タイトル終端を探す (CR+LF)
    int pos;
    for (pos = 0; pos < (int)data.length; pos++) {
        if (ptr[pos] == 0x0d && ptr[pos + 1] == 0x0a) break;
    }
    
    if (pos >= (int)data.length) return nil;
    
    NSData* titleData = [data subdataWithRange:NSMakeRange(0, pos)];
    
    // 複数のエンコーディングで試す
    NSString* title = [[NSString alloc] initWithData:titleData encoding:NSShiftJISStringEncoding];
    if (!title) title = [[NSString alloc] initWithData:titleData encoding:NSUTF8StringEncoding];
    
    return title ? title : @"(no title)";
}

// 大文字小文字を区別せずにPDXファイルを検索
static NSString* findPDXFile(NSString* pdxFileName, NSString* directory) {
    if (!pdxFileName || !directory) return nil;
    
    // 拡張子がない場合は .pdx を補完
    NSString* baseName = pdxFileName;
    if (![pdxFileName.lowercaseString hasSuffix:@".pdx"]) {
        baseName = [pdxFileName stringByAppendingString:@".pdx"];
    }
    
    // ディレクトリ内のファイルを列挙して大文字小文字を区別せずに比較
    NSString* targetLower = baseName.lowercaseString;
    NSError* error = nil;
    NSArray<NSString*>* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:&error];
    
    if (!error && contents) {
        for (NSString* file in contents) {
            if ([file.lowercaseString isEqualToString:targetLower]) {
                return [directory stringByAppendingPathComponent:file];
            }
        }
    }
    
    return nil; // 見つからない
}

@implementation MXDRVGBridge

+ (void)startWithSampleRate:(int)sampleRate {
    fprintf(stderr, "[MXDRVGBridge] startWithSampleRate: %d\n", sampleRate);
    MXDRVG_End();
    fprintf(stderr, "[MXDRVGBridge] calling MXDRVG_Start...\n");
    MXDRVG_Start(sampleRate, 0, 64 * 1024, 1024 * 1024);
    fprintf(stderr, "[MXDRVGBridge] MXDRVG_Start done\n");
    MXDRVG_TotalVolume(128);  // 音量を50%に設定（大きすぎる問題の対策）
}

+ (void)end {
    MXDRVG_End();
    g_mdxData = nil;
    g_pdxData = nil;
    memset(g_lastPDXFileName, 0, sizeof(g_lastPDXFileName));
}

+ (nullable NSString *)pdxFileName {
    if (g_lastPDXFileName[0] == '\0') return nil;
    NSString *name = [NSString stringWithUTF8String:g_lastPDXFileName];
    // "No PDX" の変種（例: (No PDX)、(No PDX).pdx など）を検出して統一
    if ([name.lowercaseString containsString:@"no pdx"]) {
        return @"No PDX";
    }
    return name;
}

+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath {
    // 最初に "No PDX" を設定（PDX未指定や読み込み失敗時に使用）
    strncpy(g_lastPDXFileName, "No PDX", sizeof(g_lastPDXFileName) - 1);
    g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';
    fprintf(stderr, "[loadMDXFile] Loading: %s\n", [mdxPath UTF8String]);
    NSData* fileData = [NSData dataWithContentsOfFile:mdxPath];
    if (!fileData) {
        fprintf(stderr, "[loadMDXFile] FAILED to load file\n");
        return nil;
    }
    fprintf(stderr, "[loadMDXFile] Loaded file, size: %lu\n", (unsigned long)fileData.length);

    NSString* mdxDir = [mdxPath stringByDeletingLastPathComponent];
    NSData* pdxData = nil;

    // MDX 内部からPDXファイル名を抽出
    const unsigned char* ptr = (const unsigned char*)fileData.bytes;
    int titleEndPos;
    for (titleEndPos = 0; titleEndPos < (int)fileData.length; titleEndPos++) {
        if (ptr[titleEndPos] == 0x0d && ptr[titleEndPos + 1] == 0x0a) break;
    }

    if (titleEndPos < (int)fileData.length) {
        int mdxBodyStartPos;
        for (mdxBodyStartPos = titleEndPos + 2; mdxBodyStartPos < (int)fileData.length; mdxBodyStartPos++) {
            if (ptr[mdxBodyStartPos] == 0x1a) break;
        }

        if (mdxBodyStartPos < (int)fileData.length) {
            mdxBodyStartPos++;  // 0x1A をスキップ

            // PDX ファイル名を抽出
            int pdxNameEnd = mdxBodyStartPos;
            while (pdxNameEnd < (int)fileData.length && ptr[pdxNameEnd] != 0) {
                pdxNameEnd++;
            }

            if (pdxNameEnd > mdxBodyStartPos) {
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
                    fprintf(stderr, "[PDX] Found PDX filename in MDX header: %s\n", [pdxFileName UTF8String]);
                    
                    // 大文字小文字を区別せずにPDXファイルを検索
                    NSString* pdxPath = findPDXFile(pdxFileName, mdxDir);
                    if (pdxPath) {
                        fprintf(stderr, "[PDX] Trying to load PDX from: %s\n", [pdxPath UTF8String]);
                        pdxData = [NSData dataWithContentsOfFile:pdxPath];
                        if (pdxData) {
                            fprintf(stderr, "[PDX] Successfully loaded PDX file, size: %lu\n", (unsigned long)pdxData.length);
                            // 成功：グローバル変数に PDX ファイル名を保存
                            strncpy(g_lastPDXFileName, [pdxFileName UTF8String], sizeof(g_lastPDXFileName) - 1);
                            g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';
                        } else {
                            fprintf(stderr, "[PDX] Failed to load PDX file\n");
                            // 失敗："No PDX" を設定
                            strncpy(g_lastPDXFileName, "No PDX", sizeof(g_lastPDXFileName) - 1);
                            g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';
                        }
                    } else {
                        fprintf(stderr, "[PDX] PDX file not found (case-insensitive search)\n");
                        // 失敗："No PDX" を設定
                        strncpy(g_lastPDXFileName, "No PDX", sizeof(g_lastPDXFileName) - 1);
                        g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';
                    }
                } else {
                    // PDX 指定がない場合は "No PDX" を設定
                    strncpy(g_lastPDXFileName, "No PDX", sizeof(g_lastPDXFileName) - 1);
                    g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';
                    fprintf(stderr, "[PDX] No PDX specified in MDX header\n");
                }
            }
        }
    }

    return [MXDRVGBridge loadMDXData:fileData pdxData:pdxData];
}

+ (nullable NSString *)loadMDXData:(NSData *)mdxData pdxData:(nullable NSData *)pdxData {
    if (!mdxData) return nil;
    
    const unsigned char* ptr = (const unsigned char*)mdxData.bytes;
    
    // タイトル終端を探す
    int titleEndPos;
    for (titleEndPos = 0; titleEndPos < (int)mdxData.length; titleEndPos++) {
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
    NSData* decompressed = decompressIfLZX(mdxBody);
    if (!decompressed) return nil;
    
    // PDX 処理（ログ追加）
    NSData* pdxDecompressed = nil;
    if (pdxData) {
        fprintf(stderr, "[PDX] Loading PDX data, original size: %lu bytes\n", (unsigned long)pdxData.length);
        pdxDecompressed = decompressIfLZX(pdxData);
        if (pdxDecompressed) {
            fprintf(stderr, "[PDX] PDX decompressed successfully, size: %lu bytes\n", (unsigned long)pdxDecompressed.length);
        } else {
            fprintf(stderr, "[PDX] PDX decompression failed, ignoring PDX\n");
            pdxData = nil;
        }
    } else {
        fprintf(stderr, "[PDX] No PDX data provided\n");
    }
    
    // ヘッダー付与
    NSData* mdxWrapped = wrapMDX(decompressed, pdxDecompressed);
    NSData* pdxWrapped = pdxDecompressed ? wrapPDX(pdxDecompressed) : nil;

    // グローバル変数に保存（ARC が自動管理）
    g_mdxData = mdxWrapped;
    g_pdxData = pdxWrapped;
    g_hasPDX = (pdxWrapped != nil) ? 1 : 0;

    // MDX/PDX データをエンジンに登録（必須: これをしないとシーケンスポインタがNULLのままクラッシュ）
    MXDRVG_SetData(
        (void*)g_mdxData.bytes, (unsigned long)g_mdxData.length,
        g_pdxData ? (void*)g_pdxData.bytes : NULL,
        g_pdxData ? (unsigned long)g_pdxData.length : 0
    );

    // タイトル抽出
    NSString* title = getTitleFromData(mdxData);
    return title;
}

+ (void)playWithLoopCount:(int)loopCount {
    if (!g_mdxData) return;

    // 総再生時間計測（内部状態を曲終端まで進めるため、直後に SetData で再初期化が必要）
    g_totalPlayTimeMs = MXDRVG_MeasurePlayTime(loopCount, 0);

    // MeasurePlayTime でシーケンスが終端まで進んだため SetData で冒頭へリセット
    MXDRVG_SetData(
        (void*)g_mdxData.bytes, (unsigned long)g_mdxData.length,
        g_pdxData ? (void*)g_pdxData.bytes : NULL,
        g_pdxData ? (unsigned long)g_pdxData.length : 0
    );

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
    return g_totalPlayTimeMs;
}

+ (int)getPCM:(int16_t *)buf frameCount:(int)frameCount {
    if (frameCount > 1024) frameCount = 1024;
    return MXDRVG_GetPCM(buf, frameCount);
}

+ (void)getChannelStates:(MP4MChannelState *)states {
    if (!states) return;
    memset(states, 0, sizeof(MP4MChannelState) * 16);

    // Get OPM channel states (FM 8ch)
    MP4MChannelState opmStates[8];
    memset(opmStates, 0, sizeof(opmStates));

    // Get PCM8 channel states (channels 8-15) from MXDRVG work area
    // MXDRVG_WORK_CH: S0016 (flags, bit3=keyon), S0012 (note+D, UWORD), S0018 (ch, bits 0-2 for ch number)
    MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
    MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
    MXDRVG_WORK_GLOBAL* globalWork = (MXDRVG_WORK_GLOBAL*)MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL);

    OPM_GetChannelStates(opmStates, 8);

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
        MXDRVG_WORK_GLOBAL* globalWork = (MXDRVG_WORK_GLOBAL*)MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL);
        uint16_t channelMask = globalWork ? globalWork->L001e1a : 0;

        for (int i = 0; i < 8; i++) {
            // 配列インデックス i がそのまま PCM1-8ch に対応
            // i=0 → PDX1ch (ch9), i=1 → PDX2ch (ch10), ..., i=7 → PDX8ch (ch16)
            int chIdx = 8 + i;  // Map array index directly to display positions
            int pcmBit = 8 + i;  // PCM channel bit position (bit 8-15)

            // チャンネルマスクでこの PCM チャンネルが有効か確認
            int isChannelEnabled = (channelMask & (1 << pcmBit)) ? 1 : 0;

            if (!isChannelEnabled || !g_hasPDX) {
                // このチャンネルはマスクで無効化されている、または PDX がない
                states[chIdx].keyOn = 0;
                states[chIdx].active = 0;
                states[chIdx].volume = 0;
                states[chIdx].velocity = 0;
                continue;
            }

            uint8_t flags = pcmCh[i].S0016;
            uint8_t keyOn = (flags >> 3) & 1;  // bit3 = keyon

            // PCM チャンネルが使用可能か判定
            UBYTE volatile* S0000 = pcmCh[i].S0000;  // Ptr フィールド
            uint8_t vol = pcmCh[i].S0022;  // volume
            uint8_t len = pcmCh[i].S001a;  // len

            // 実際に割り当て済みか判定：S0000 ポインタが有効（非ゼロ）
            // S0000 はサンプルデータへのポインタ。ゼロなら割り当てなし
            uint8_t isPlaying = (S0000 != NULL && S0000 != 0) ? 1 : 0;

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

            // Volume: 実際に再生中のときは 127、オフのときは 0
            states[chIdx].volume = isPlaying ? 127 : 0;
            // Spectrum analyzer用：再生中は 127、オフは 0（FM と統一）
            states[chIdx].velocity = isPlaying ? 127 : 0;
        }
    }
}

+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted {
    if (ch < 0 || ch >= 16) return;

    if (ch < 8) {
        // FM チャンネル (0-7): YM2151 TL (Total Level) レジスタで制御
        MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
        if (!fmCh) return;

        if (isMuted) {
            if (!g_fmMuteState[ch]) {
                // マュート開始：元の TL 値を保存して TL=127 に設定
                // FM ワークエリアの S001f (TL) フィールド
                uint8_t currentTL = fmCh[ch].S001f;
                g_fmMutedTL[ch] = currentTL;
                g_fmMuteState[ch] = 1;
                fmCh[ch].S001f = 127;  // 無音（最大減衰）
            }
        } else {
            if (g_fmMuteState[ch]) {
                // マュート解除：保存した TL 値に復元
                fmCh[ch].S001f = g_fmMutedTL[ch];
                g_fmMuteState[ch] = 0;
            }
        }
    } else {
        // PCM チャンネル (8-15): volume で制御
        MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
        if (!pcmCh) return;

        int pcmIdx = ch - 8;
        if (pcmIdx < 0 || pcmIdx >= 8) return;

        if (isMuted) {
            if (!g_pcmMuteState[pcmIdx]) {
                // マュート開始：元の volume を保存して 0 に設定
                uint8_t currentVol = pcmCh[pcmIdx].S0022;
                g_pcmMutedVol[pcmIdx] = currentVol;
                g_pcmMuteState[pcmIdx] = 1;
                pcmCh[pcmIdx].S0022 = 0;  // 無音
            }
        } else {
            if (g_pcmMuteState[pcmIdx]) {
                // マュート解除：保存した volume に復元
                pcmCh[pcmIdx].S0022 = g_pcmMutedVol[pcmIdx];
                g_pcmMuteState[pcmIdx] = 0;
            }
        }
    }
}

@end
