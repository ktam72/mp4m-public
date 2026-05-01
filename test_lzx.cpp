//
// test_lzx.cpp - LZX 展開テスト
//

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>>
#include "Vendor/lzx/lzx042.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: test_lzx <mdx_file>\n");
        return 1;
    }

    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Cannot open file: %s\n", argv[1]);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    size_t fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t* data = (uint8_t*)malloc(fsize);
    if (!data || fread(data, 1, fsize, f) != fsize) {
        fprintf(stderr, "Cannot read file\n");
        return 1;
    }
    fclose(f);

    // LZX チェック
    unsigned int decompLen = lzx042check(data);
    printf("File size: %zu bytes\n", fsize);
    printf("LZX decompressed size: %u bytes\n", decompLen);

    if (decompLen > 0) {
        printf("File is LZX compressed\n");
        
        uint8_t* decompBuf = (uint8_t*)malloc(decompLen);
        unsigned int ret = lzx042decode(decompBuf, decompLen, data, (unsigned)fsize);
        printf("Decompressed: %u bytes\n", ret);
        
        free(decompBuf);
    } else {
        printf("File is NOT LZX compressed (raw data)\n");
    }

    free(data);
    return 0;
}
