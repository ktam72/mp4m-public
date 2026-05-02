//
// test_lzx_compare.cpp - lzx042 とオリジナルlzx のデコード結果比較
//

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

// lzx042 (C API)
extern "C" {
#include "Vendor/lzx/lzx042.h"
}

// オリジナルlzx (C++ API)
#include "Vendor/lzx/lzx.h"

void print_hex(const uint8_t* data, size_t len, size_t offset) {
    printf("Offset 0x%06zx: ", offset);
    for (size_t i = 0; i < len && i < 16; i++) {
        printf("%02x ", data[offset + i]);
    }
    printf("\n");
}

int main(int argc, char* argv[]) {
    const char* mdx_path = "/Users/ktam/Downloads/MDX/Arsys/Knight_Arms/KNA03A.MDX";
    
    if (argc >= 2) {
        mdx_path = argv[1];
    }

    printf("=== LZX Decode Comparison Test ===\n");
    printf("File: %s\n\n", mdx_path);

    // ファイル読み込み
    FILE* f = fopen(mdx_path, "rb");
    if (!f) {
        fprintf(stderr, "Cannot open file: %s\n", mdx_path);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    size_t fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t* data = (uint8_t*)malloc(fsize);
    if (!data || fread(data, 1, fsize, f) != fsize) {
        fprintf(stderr, "Cannot read file\n");
        fclose(f);
        return 1;
    }
    fclose(f);

    printf("File size: %zu bytes\n", fsize);

    // --- lzx042 でデコード ---
    unsigned int decompLen042 = lzx042check(data);
    printf("\nlzx042 check: %u bytes\n", decompLen042);

    uint8_t* decomp042 = nullptr;
    unsigned int ret042 = 0;
    bool is_compressed042 = (decompLen042 > 0);
    
    if (is_compressed042) {
        decomp042 = (uint8_t*)malloc(decompLen042);
        if (decomp042) {
            ret042 = lzx042decode(decomp042, decompLen042, data, (unsigned)fsize);
            printf("lzx042 decode: %u bytes\n", ret042);
        }
    } else {
        printf("lzx042: Not LZX compressed (raw data)\n");
        decompLen042 = (unsigned int)fsize;
        decomp042 = (uint8_t*)malloc(decompLen042);
        if (decomp042) {
            memcpy(decomp042, data, fsize);
            ret042 = (unsigned int)fsize;
        }
    }

    // --- オリジナルlzx でデコード ---
    unsigned int decompLenOrig = lzx::check(data, fsize);
    printf("\nOriginal lzx check: %u bytes\n", decompLenOrig);

    uint8_t* decompOrig = nullptr;
    unsigned int retOrig = 0;
    bool is_compressed_orig = (decompLenOrig > 0);
    
    if (is_compressed_orig) {
        decompOrig = (uint8_t*)malloc(decompLenOrig);
        if (decompOrig) {
            retOrig = lzx::decompress(decompOrig, decompLenOrig, data, fsize);
            printf("Original lzx decode: %u bytes\n", retOrig);
        }
    } else {
        printf("Original lzx: Not LZX compressed (raw data)\n");
        decompLenOrig = (unsigned int)fsize;
        decompOrig = (uint8_t*)malloc(decompLenOrig);
        if (decompOrig) {
            memcpy(decompOrig, data, fsize);
            retOrig = (unsigned int)fsize;
        }
    }

    // --- 比較 ---
    printf("\n=== Comparison Result ===\n");
    
    if (ret042 == 0 || retOrig == 0) {
        printf("❌ Decode failed (042: %u, Orig: %u)\n", ret042, retOrig);
        free(decomp042);
        free(decompOrig);
        free(data);
        return 1;
    }

    if (ret042 != retOrig) {
        printf("❌ Decoded size mismatch (042: %u, Orig: %u)\n", ret042, retOrig);
        free(decomp042);
        free(decompOrig);
        free(data);
        return 1;
    }

    // バイトごとに比較
    size_t diff_count = 0;
    size_t first_diff = 0;
    for (unsigned int i = 0; i < ret042; i++) {
        if (decomp042[i] != decompOrig[i]) {
            if (diff_count == 0) {
                first_diff = i;
            }
            diff_count++;
            if (diff_count <= 5) {
                printf("First diff at offset 0x%x: 042=0x%02x, Orig=0x%02x\n", 
                       i, decomp042[i], decompOrig[i]);
            }
        }
    }

    if (diff_count == 0) {
        printf("✅ Perfect match! %u bytes identical\n", ret042);
        
        // ヘッダー情報を表示
        printf("\n--- Decoded MDX Header Info ---\n");
        if (ret042 > 0x20) {
            // タイトル部分を表示 (Shift-JIS)
            printf("Title (Shift-JIS): ");
            for (unsigned int i = 0; i < 0x20 && i < ret042; i++) {
                if (decompOrig[i] == 0x0d || decompOrig[i] == 0x0a) break;
                printf("%c", decompOrig[i]);
            }
            printf("\n");
            
            // 0x1A (Ctrl+Z) の位置を確認
            for (unsigned int i = 0; i < ret042; i++) {
                if (decompOrig[i] == 0x1a) {
                    printf("0x1A found at offset 0x%x\n", i);
                    break;
                }
            }
        }
    } else {
        printf("❌ Mismatch found: %zu bytes different (%.2f%%)\n", 
               diff_count, (diff_count * 100.0) / ret042);
        printf("First difference at offset 0x%zx\n", first_diff);
        
        // 周辺のデータを表示
        printf("\nContext around first difference:\n");
        size_t start = first_diff > 8 ? first_diff - 8 : 0;
        size_t end = first_diff + 8 < ret042 ? first_diff + 8 : ret042;
        
        printf("lzx042: ");
        print_hex(decomp042, end - start, start);
        printf("Orig  : ");
        print_hex(decompOrig, end - start, start);
    }

    free(decomp042);
    free(decompOrig);
    free(data);
    
    return 0;
}
