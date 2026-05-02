//
//  MXDRVGBridge.m
//  ObjC wrapper for MXDRVG + LZX (MDXPlayer-main から流用)
//

#import "MXDRVGBridge.h"
#include "../Vendor/gamdx/jni/mxdrvg/mxdrvg.h"
#include "../Vendor/lzx/lzx.h"
#include "../Vendor/opm/opm_wrapper.h"
#include <stdlib.h>
#include <string.h>

extern void OPM_GetChannelStates(MP4MChannelState* states, int max_channels);

// グローバル状態
static NSData* g_mdxData = nil;
static NSData* g_pdxData = nil;
static char g_lastTitle[512] = {0};
static int g_totalPlayTimeMs = 0;

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
}

+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath {
    NSData* fileData = [NSData dataWithContentsOfFile:mdxPath];
    if (!fileData) return nil;

    // 同じディレクトリから PDX を探してロード（大文字小文字両方試す）
    NSString* basePath = [mdxPath stringByDeletingPathExtension];
    NSData* pdxData = [NSData dataWithContentsOfFile:[basePath stringByAppendingPathExtension:@"pdx"]];
    if (!pdxData) {
        pdxData = [NSData dataWithContentsOfFile:[basePath stringByAppendingPathExtension:@"PDX"]];
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
    
    // Get PCM8 channel states (channels 8-15) from MXDRVG work area
    // MXDRVG_WORK_CH: S0016 (flags, bit3=keyon), S0012 (note+D, UWORD)
    MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
    if (pcmCh) {
        for (int i = 0; i < 8; i++) {
            int chIdx = 8 + i;
            uint8_t flags = pcmCh[i].S0016;
            uint8_t keyOn = (flags >> 3) & 1;  // bit3 = keyon
            states[chIdx].keyOn = keyOn;
            states[chIdx].active = keyOn;
            
            // note+D is UWORD, lower bits = note
            uint16_t noteD = pcmCh[i].S0012;
            states[chIdx].keyCode = noteD & 0x7F;
            
            // Pan from PCM8 channel mode
            int mode = MXDRVG_GetPcm8ChannelMode(i);
            states[chIdx].pan = (mode & 3) ? (mode & 3) : 3;  // Default L+R
            
            // Volume (PCM doesn't have TL, estimate from keyOn)
            states[chIdx].volume = keyOn ? 64 : 127;
            states[chIdx].velocity = keyOn ? 100 : 0;
        }
    }
    
    // Debug log
    static int callCount = 0;
    if (callCount++ % 60 == 0) {
        fprintf(stderr, "[ChannelStates] FM0: on=%d kc=%d | FM1: on=%d | PCM8: on=%d kc=%d\n",
                states[0].keyOn, states[0].keyCode, states[1].keyOn,
                states[8].keyOn, states[8].keyCode);
    }
}

@end
