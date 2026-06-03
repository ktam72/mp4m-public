//
//  MDXFileLoader.h
//  MDX/PDX ファイルの読み込み・パース・展開を担当するユーティリティ
//
//  MXDRVGBridge.mm からパーサー関連のロジックを分離するためのクラス。
//  このクラスはオーディオ再生パスに一切依存しない。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MDXFileLoader : NSObject

/// LZX 圧縮されたデータを展開する（必要に応じて）
/// @param data 入力データ（LZX 圧縮または非圧縮）
/// @return 展開後データ。展開不要の場合は入力そのまま
+ (nullable NSData *)decompressIfLZX:(NSData *)data;

/// MDX データに PDX ヘッダを付与する
+ (NSData *)wrapMDX:(NSData *)body pdxData:(nullable NSData *)pdx;

/// PDX データにヘッダを付与する
+ (NSData *)wrapPDX:(NSData *)body;

/// MDX データからタイトル文字列を抽出する（CR+LF まで）
+ (nullable NSString *)titleFromData:(NSData *)data;

/// PDX ファイル名として有効かチェック（パストラバーサル対策）
+ (BOOL)isValidPDXFileName:(NSString *)fileName;

/// 指定ディレクトリから PDX ファイルを検索（大文字小文字無視）
+ (nullable NSString *)findPDXFile:(NSString *)pdxFileName
                         inDirectory:(NSString *)directory;

@end

NS_ASSUME_NONNULL_END
