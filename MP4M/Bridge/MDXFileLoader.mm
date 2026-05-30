//
//  MDXFileLoader.mm
//  MDX/PDX ファイルの読み込み・パース・展開ユーティリティ
//
//  MXDRVGBridge.mm から分離したパーサー関連ロジック。
//  このファイルはオーディオ再生パスに一切依存しない。
//

#import "MDXFileLoader.h"
#include "../Vendor/lzx/lzx.h"
#include <stdlib.h>
#include <string.h>

@implementation MDXFileLoader

+ (nullable NSData *)decompressIfLZX:(NSData *)data {
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

+ (NSData *)wrapMDX:(NSData *)body pdxData:(nullable NSData *)pdx {
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

+ (NSData *)wrapPDX:(NSData *)body {
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

+ (nullable NSString *)titleFromData:(NSData *)data {
    if (!data) return nil;
    
    const unsigned char* ptr = (const unsigned char*)data.bytes;
    
    // タイトル終端を探す (CR+LF)
    int pos;
    for (pos = 0; pos < (int)data.length - 1; pos++) {  // 境界チェック済み
        if (ptr[pos] == 0x0d && ptr[pos + 1] == 0x0a) break;
    }
    
    if (pos >= (int)data.length) return nil;
    
    NSData* titleData = [data subdataWithRange:NSMakeRange(0, pos)];
    
    // 複数のエンコーディングで試す
    NSString* title = [[NSString alloc] initWithData:titleData encoding:NSShiftJISStringEncoding];
    if (!title) title = [[NSString alloc] initWithData:titleData encoding:NSUTF8StringEncoding];
    
    return title ? title : @"(no title)";
}

+ (BOOL)isValidPDXFileName:(NSString *)fileName {
    if (!fileName || fileName.length == 0) return NO;

    // パスセパレータを含まないか確認
    if ([fileName rangeOfString:@"/"].location != NSNotFound) return NO;
    if ([fileName rangeOfString:@"\\"].location != NSNotFound) return NO;

    // .. （ディレクトリトラバーサル）を含まないか確認
    if ([fileName rangeOfString:@".."].location != NSNotFound) return NO;

    // null 文字を含まないか確認
    if ([fileName rangeOfString:@"\0"].location != NSNotFound) return NO;

    return YES;
}

+ (nullable NSString *)findPDXFile:(NSString *)pdxFileName
                         inDirectory:(NSString *)directory {
    if (!pdxFileName || !directory) return nil;

    // 拡張子がない場合は .pdx を補完
    NSString* baseName = pdxFileName;
    if (![pdxFileName.lowercaseString hasSuffix:@".pdx"]) {
        baseName = [pdxFileName stringByAppendingString:@".pdx"];
        #ifdef DEBUG
        fprintf(stderr, "[PDX] Extension completed: %s -> %s\n", [pdxFileName UTF8String], [baseName UTF8String]);
        #endif
    }

    // ディレクトリ内のファイルを列挙して大文字小文字を区別せずに比較
    NSString* targetLower = baseName.lowercaseString;
    NSError* error = nil;
    NSArray<NSString*>* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:&error];

    if (!error && contents) {
        for (NSString* file in contents) {
            if ([file.lowercaseString isEqualToString:targetLower]) {
                #ifdef DEBUG
                fprintf(stderr, "[PDX] Found file: %s\n", [file UTF8String]);
                #endif
                return [directory stringByAppendingPathComponent:file];
            }
        }
    }

    #ifdef DEBUG
    fprintf(stderr, "[PDX] File not found: %s (searched in %s)\n", [baseName UTF8String], [directory UTF8String]);
    #endif
    return nil; // 見つからない
}

@end
