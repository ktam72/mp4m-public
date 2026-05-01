//
//  MXDRVGBridge.m
//  ObjC wrapper for MXDRVG + LZX (MDXPlayer-main から流用)
//

#import "MXDRVGBridge.h"
#include "../Vendor/gamdx/jni/mxdrvg/mxdrvg.h"
#include "../Vendor/lzx/lzx.h"
#include <stdlib.h>
#include <string.h>

static NSMutableData* g_mdxData = NULL;
static NSMutableData* g_pdxData = NULL;
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
    MXDRVG_End();
    MXDRVG_Start(sampleRate, 0, 64 * 1024, 1024 * 1024);
    MXDRVG_TotalVolume(256);  // 最大音量設定
}

+ (void)end {
    MXDRVG_End();
    g_mdxData = NULL;
    g_pdxData = NULL;
}

+ (nullable NSString *)loadMDXFile:(NSString *)mdxPath {
    NSData* fileData = [NSData dataWithContentsOfFile:mdxPath];
    if (!fileData) return nil;
    
    return [MXDRVGBridge loadMDXData:fileData pdxData:nil];
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
    
    // PDX 処理
    NSData* pdxDecompressed = nil;
    if (pdxData) {
        pdxDecompressed = decompressIfLZX(pdxData);
    }
    
    // ヘッダー付与
    NSData* mdxWrapped = wrapMDX(decompressed, pdxDecompressed);
    NSData* pdxWrapped = pdxDecompressed ? wrapPDX(pdxDecompressed) : nil;
    
    // グローバル変数に保存
    g_mdxData = (NSMutableData*)mdxWrapped;
    g_pdxData = (NSMutableData*)pdxWrapped;
    
    // タイトル抽出
    NSString* title = getTitleFromData(mdxData);
    return title;
}

+ (void)playWithLoopCount:(int)loopCount {
    if (!g_mdxData) return;
    
    // 総再生時間計測
    g_totalPlayTimeMs = MXDRVG_MeasurePlayTime(loopCount, 0);
    
    // 直後に PlayAt を呼ぶ（SetData は再度呼ばない）
    MXDRVG_PlayAt(0, loopCount, 1);  // 3番目パラメータ = 1 (フェードアウト ON)
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
    return (int)MXDRVG_GetPlayAt();
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
}

@end
