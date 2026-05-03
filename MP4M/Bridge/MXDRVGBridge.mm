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
    return [NSString stringWithUTF8String:g_lastPDXFileName];
}

+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath {
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
                    // グローバル変数に PDX ファイル名を保存
                    strncpy(g_lastPDXFileName, [pdxFileName UTF8String], sizeof(g_lastPDXFileName) - 1);
                    g_lastPDXFileName[sizeof(g_lastPDXFileName) - 1] = '\0';

                    NSString* pdxPath = [mdxDir stringByAppendingPathComponent:pdxFileName];
                    fprintf(stderr, "[PDX] Trying to load PDX from: %s\n", [pdxPath UTF8String]);
                    pdxData = [NSData dataWithContentsOfFile:pdxPath];
                    if (pdxData) {
                        fprintf(stderr, "[PDX] Successfully loaded PDX file, size: %lu\n", (unsigned long)pdxData.length);
                    } else {
                        fprintf(stderr, "[PDX] Failed to load PDX file\n");
                    }
                } else {
                    fprintf(stderr, "[PDX] Failed to decode PDX filename from MDX header\n");
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

    static int debugLogCount = 0;
    if (debugLogCount++ % 60 == 0) {
        fprintf(stderr, "[WORK_AREA_PTR] FM=%p, PCM=%p, hasPDX=%d\n", fmCh, pcmCh, g_hasPDX);
        if (globalWork) {
            // チャンネルマスク（L001e06）を確認: PCM1（bit8）が有効か？
            uint16_t channelMask = globalWork->L001e06;
            uint16_t channelEnable = globalWork->L001e1a;
            uint8_t pcm1Enabled = (channelMask >> 8) & 1;
            fprintf(stderr, "[CHANNEL_MASK] mask=0x%04x, enable=0x%04x, PCM1_bit8=%d\n",
                channelMask, channelEnable, pcm1Enabled);
        }
        if (fmCh) {
            fprintf(stderr, "[FM_RAW_CH0] S0016=%02x, S0012=%04x, S0022=%02x, S0018=%02x\n",
                fmCh[0].S0016, fmCh[0].S0012, fmCh[0].S0022, fmCh[0].S0018);
        }
        if (pcmCh) {
            fprintf(stderr, "[PCM_RAW_CH0] S0016=%02x, S0012=%04x, S0022=%02x, S0018=%02x\n",
                pcmCh[0].S0016, pcmCh[0].S0012, pcmCh[0].S0022, pcmCh[0].S0018);
        }
    }

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

    static int logCount = 0;
    if (logCount++ % 60 == 0) {
        fprintf(stderr, "[PCM_AREA] pcmCh=%p, hasPDX=%d\n", pcmCh, g_hasPDX);
        if (pcmCh && g_hasPDX) {
            fprintf(stderr, "[PCM_DETAILED_ANALYSIS] ");
            for (int i = 0; i < 8; i++) {
                uint8_t len = pcmCh[i].S001a;
                uint8_t chNum = pcmCh[i].S0018 & 0x7F;
                uint8_t flags16 = pcmCh[i].S0016;
                uint8_t flags17 = pcmCh[i].S0017;
                uint8_t gate = pcmCh[i].S001b;
                uint16_t noteD = pcmCh[i].S0012;
                UBYTE volatile* S0000 = pcmCh[i].S0000;
                UBYTE volatile* S0004 = pcmCh[i].S0004;
                fprintf(stderr, "ch%d(len=%d,num=%d,f16=%02x,f17=%02x,gate=%02x,noteD=%04x,S0000=%p,S0004=%p) ",
                    i, len, chNum, flags16, flags17, gate, noteD, S0000, S0004);
            }
            fprintf(stderr, "\n");

            // 動的フィールド分析：S0022(v), S0008(bend), S001f(keyon_delay), S0020(keyon_delay_counter)
            fprintf(stderr, "[PCM_DYNAMIC_FIELDS] ");
            for (int i = 0; i < 8; i++) {
                uint32_t bendDelta = pcmCh[i].S0008;
                uint8_t vol = pcmCh[i].S0022;
                uint8_t keyonDelay = pcmCh[i].S001f;
                uint8_t keyonCounter = pcmCh[i].S0020;
                fprintf(stderr, "ch%d(bend=%lu,vol=%d,delay=%d,counter=%d) ",
                    i, bendDelta, vol, keyonDelay, keyonCounter);
            }
            fprintf(stderr, "\n");

            // PDX ファイルサイズと実際のサンプル構成を確認
            MXDRVG_WORK_GLOBAL* globalWork = (MXDRVG_WORK_GLOBAL*)MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL);
            if (globalWork) {
                // グローバルワーク情報はログ出力しない（本番環境では不要）
            }

            // PCM8 エンジンの実際の再生状態を確認
            // MXDRVG_WORKADR_PCM8 は X68K::X68PCM8 オブジェクトを返すはず
            volatile void* pcm8Work = MXDRVG_GetWork(MXDRVG_WORKADR_PCM8);
            if (pcm8Work) {
                fprintf(stderr, "[PCM8_ENGINE] pcm8=%p\n", pcm8Work);
                // pcm8Work は X68K::X68PCM8* として解釈できるが、
                // Pcm8 クラスの内部構造は隠蔽されているため直接アクセスは困難
                // ここは参考情報として出力するのみ
            }
        }
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
    } else {
        fprintf(stderr, "[getChannelStates] WARNING: PCM work area is NULL\n");
    }
    
    // Debug log for PAN detection
    static int callCount = 0;
    if (callCount++ % 60 == 0) {
        fprintf(stderr, "[LevelMeter] ");
        for (int i = 0; i < 16; i++) {
            // 表示％を計算（LevelMeterView の計算と同じ）
            double levelPercent = 0.0;
            const char* panLabel = "N";  // No signal

            if (states[i].keyOn) {
                double v = (double)states[i].volume / 127.0;
                levelPercent = pow(v, 3.0) * 100.0;  // パーセンテージに変換

                // PAN ラベル
                switch (states[i].pan) {
                    case 0: panLabel = "L"; break;      // Left
                    case 2: panLabel = "R"; break;      // Right
                    case 3: panLabel = "S"; break;      // Stereo (L+R)
                    default: panLabel = "C"; break;     // Center
                }
            }

            fprintf(stderr, "ch%d:%5.1f%% %s ", i+1, levelPercent, panLabel);
        }
        fprintf(stderr, "\n");

        // FM チャンネルの keyOn フラグと PAN 情報をログ出力
        MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
        if (fmCh) {
            fprintf(stderr, "[FM_DEBUG] ");
            for (int i = 0; i < 8; i++) {
                uint8_t flags16 = fmCh[i].S0016;
                uint8_t keyOn = (flags16 >> 3) & 1;
                uint8_t p = fmCh[i].S001c;
                uint8_t pan_bits = p & 0x03;
                const char* pan_label = "?";
                if (pan_bits == 0x01) pan_label = "L";
                else if (pan_bits == 0x02) pan_label = "R";
                else pan_label = "C";
                fprintf(stderr, "FM%d(keyOn=%d,pan=%s) ", i+1, keyOn, pan_label);
            }
            fprintf(stderr, "\n");
        }

        // PCM チャンネルの keyOn フラグと PAN 情報をログ出力
        if (pcmCh) {
            fprintf(stderr, "[PCM_DEBUG] ");
            for (int i = 0; i < 8; i++) {
                UBYTE volatile* S0000 = pcmCh[i].S0000;
                int keyOn = (S0000 != NULL && S0000 != 0) ? 1 : 0;
                int mode = MXDRVG_GetPCM8ChannelMode(i);
                uint8_t pan_bits = mode & 0x03;
                const char* pan_label = "?";
                if (pan_bits == 0x01) {
                    pan_label = "L";
                } else if (pan_bits == 0x02) {
                    pan_label = "R";
                } else if (pan_bits == 0x03) {
                    pan_label = "S";
                } else {
                    pan_label = "C";
                }
                fprintf(stderr, "PDX%d(keyOn=%d,pan=%s) ", i+1, keyOn, pan_label);
            }
            fprintf(stderr, "\n");
        }
    }
}

@end
