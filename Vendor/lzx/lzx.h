//
//  lzx.h
//  X68000 MDX 用 LZX 解凍 (0BSD ライセンス)
//
//  lzx042 のロジックをC++で清潔に再実装
//  X68000 独自の LZX バリアント対応
//

#ifndef LZX_H
#define LZX_H

#include <cstdint>
#include <cstddef>

namespace lzx {

/// MDX ファイルが LZX 圧縮されているか判定
/// @param data  MDX ファイルデータのポインタ
/// @param len   MDX ファイルのサイズ
/// @return      LZX 圧縮済みの場合は展開後のサイズ、圧縮されていない場合は 0
unsigned int check(const uint8_t* data, size_t len);

/// LZX 圧縮データを展開
/// @param output        展開先バッファのポインタ
/// @param output_len    展開先バッファのサイズ
/// @param input         圧縮データのポインタ
/// @param input_len     圧縮データのサイズ
/// @return              展開したバイト数（失敗時は 0）
unsigned int decompress(uint8_t* output, size_t output_len,
                        const uint8_t* input, size_t input_len);

}

#endif // LZX_H
