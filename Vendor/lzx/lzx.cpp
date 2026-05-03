//
//  lzx.cpp
//  X68000 MDX 用 LZX 解凍 (0BSD ライセンス)
//
//  X68000 独自の LZX バリアント対応
//

#include "lzx.h"

namespace lzx {

/// ビットストリーム読み込み用ヘルパークラス
class BitReader {
public:
    BitReader(const uint8_t* data, size_t len)
        : current_(data), end_(data + len), bit_buffer_(0), bit_count_(0) {}

    /// 1ビット読み込む
    bool read_bit() {
        if (bit_count_ == 0) {
            if (current_ >= end_) return false;
            bit_buffer_ = *current_++;
            bit_count_ = 8;
        }
        bool bit = (bit_buffer_ >> (--bit_count_)) & 1;
        return bit;
    }

    /// 1バイト読み込む
    bool read_byte(uint8_t& byte) {
        if (current_ >= end_) return false;
        byte = *current_++;
        return true;
    }

    bool is_eof() const {
        return current_ >= end_;
    }

private:
    const uint8_t* current_;
    const uint8_t* end_;
    uint8_t bit_buffer_;
    int bit_count_;
};

unsigned int check(const uint8_t* data, size_t len) {
    if (len < 22) return 0;
    
    // LZX シグネチャを確認: bytes[4..7] = "LZX "
    if (data[4] != 0x4c || data[5] != 0x5a || data[6] != 0x58 || data[7] != 0x20) {
        return 0;
    }
    
    // 展開後のサイズを bytes[0x12..0x15] から取得
    unsigned int decompressed_size = 
        ((unsigned int)data[0x12] << 24) |
        ((unsigned int)data[0x13] << 16) |
        ((unsigned int)data[0x14] << 8) |
        data[0x15];
    
    return decompressed_size;
}

unsigned int decompress(uint8_t* output, size_t output_len,
                        const uint8_t* input, size_t input_len) {
    if (!output || !input || input_len < 0x26) {
        return 0;
    }

    uint8_t* out_pos = output;
    uint8_t* out_end = output + output_len;
    const uint8_t* in_pos = input;
    const uint8_t* in_end = input + input_len;
    const uint8_t* data_start = output;  // 相対参照用の基準位置

    // ヘッダーをスキップして、マーカー 0x7F 0xFF 0xFF 0x4C を探す
    in_pos += 0x26;
    while (in_pos + 3 < in_end) {
        if (in_pos[0] == 0x7f && in_pos[1] == 0xff && in_pos[2] == 0xff && in_pos[3] == 0x4c) {
            break;
        }
        in_pos += 2;
    }
    if (in_pos + 3 >= in_end) {
        return 0;  // マーカーが見つからない
    }
    in_pos += 4;  // マーカーをスキップ

    BitReader reader(in_pos, in_end - in_pos);

    while (!reader.is_eof()) {
        bool is_literal = reader.read_bit();

        if (is_literal) {
            // リテラルバイト
            uint8_t byte;
            if (!reader.read_byte(byte)) return 0;
            if (out_pos >= out_end) return 0;
            *out_pos++ = byte;
        } else {
            bool extended = reader.read_bit();

            int offset;
            unsigned int count;

            if (!extended) {
                // 短い参照: 2-5 バイト
                bool bit0 = reader.read_bit();
                bool bit1 = reader.read_bit();
                count = (bit0 ? 2 : 0) + (bit1 ? 1 : 0) + 2;
                
                uint8_t offset_byte;
                if (!reader.read_byte(offset_byte)) return 0;
                offset = offset_byte - 256;  // Line 66
            } else {
                // 長い参照: 2+ バイト
                uint8_t offset_hi, offset_lo;
                if (!reader.read_byte(offset_hi)) return 0;
                if (!reader.read_byte(offset_lo)) return 0;

                offset = (offset_hi << 5) + (offset_lo >> 3);
                offset -= (1 << 13);  // Line 73
                count = (offset_lo & 7) + 2;

                if (count == 2) {
                    // 拡張カウント
                    if (!reader.read_byte(offset_lo)) return 0;
                    count = offset_lo + 1;
                    if (count == 1) {
                        return (unsigned int)(out_pos - data_start);
                    }
                }
            }

            if (out_pos + offset < data_start) {
                return 0;  // 範囲外参照
            }

            while (count-- > 0) {
                if (out_pos >= out_end) return 0;
                *out_pos++ = out_pos[offset];
            }
        }
    }

    return (unsigned int)(out_pos - data_start);
}

}  // namespace lzx
