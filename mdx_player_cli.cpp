//
// mdx_player_cli.cpp - MDX Player CLI (debug version)
//

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>

#include "Vendor/lzx/lzx.h"
#include "Vendor/gamdx/jni/mxdrvg/mxdrvg.h"

struct MDXWrapper {
    uint8_t header[10];
    std::vector<uint8_t> data;
};

MDXWrapper wrapMDX(const uint8_t* body, size_t bodyLen, bool hasPDX) {
    MDXWrapper wrap;
    wrap.header[0] = 0x00;
    wrap.header[1] = 0x00;
    wrap.header[2] = hasPDX ? 0x00 : 0xff;
    wrap.header[3] = hasPDX ? 0x00 : 0xff;
    wrap.header[4] = 0x00;
    wrap.header[5] = 0x0a;
    wrap.header[6] = 0x00;
    wrap.header[7] = 0x08;
    wrap.header[8] = 0x00;
    wrap.header[9] = 0x00;
    
    wrap.data.resize(10 + bodyLen);
    memcpy(wrap.data.data(), wrap.header, 10);
    memcpy(wrap.data.data() + 10, body, bodyLen);
    return wrap;
}

uint8_t* decompress_if_lzx(const uint8_t* data, size_t len, size_t& outLen) {
    if (len < 0x16) {
        outLen = len;
        uint8_t* buf = (uint8_t*)malloc(len);
        if (buf) memcpy(buf, data, len);
        return buf;
    }

    // Check if LZX compressed
    unsigned int decompLen = lzx::check(data, len);
    if (decompLen == 0) {
        // Not LZX compressed, return as-is
        outLen = len;
        uint8_t* buf = (uint8_t*)malloc(len);
        if (buf) memcpy(buf, data, len);
        return buf;
    }

    if (decompLen > 1024 * 1024) {
        printf("ERROR: Decompressed size too large: %u bytes\n", decompLen);
        return NULL;
    }

    uint8_t* buf = (uint8_t*)malloc(decompLen);
    if (!buf) {
        printf("ERROR: malloc failed for %u bytes\n", decompLen);
        return NULL;
    }

    unsigned int ret = lzx::decompress(buf, decompLen, data, len);
    if (ret == 0) {
        printf("ERROR: lzx::decompress failed\n");
        free(buf);
        return NULL;
    }

    outLen = ret;
    printf("LZX decompressed: %zu → %u bytes\n", len, ret);
    return buf;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: mdx_player_cli <mdx_file> [-o output.wav]\n");
        return 1;
    }

    const char* mdx_path = argv[1];
    const char* output_path = "output.wav";
    
    // -o オプション処理
    for (int i = 2; i < argc - 1; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            output_path = argv[i + 1];
            break;
        }
    }

    FILE* f = fopen(mdx_path, "rb");
    if (!f) {
        printf("ERROR: Cannot open file: %s\n", mdx_path);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    size_t fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t* raw_data = (uint8_t*)malloc(fsize);
    if (!raw_data || fread(raw_data, 1, fsize, f) != fsize) {
        printf("ERROR: Cannot read file\n");
        return 1;
    }
    fclose(f);

    printf("File: %s (%zu bytes)\n", mdx_path, fsize);

    const uint8_t* p = raw_data;
    
    int pos = 0;
    for (; pos + 1 < (int)fsize; pos++) {
        if (p[pos] == 0x0d && p[pos + 1] == 0x0a) break;
    }
    if (pos >= (int)fsize - 1) {
        printf("ERROR: Invalid MDX format\n");
        return 1;
    }

    const uint8_t* mdx_start = p + pos + 2;
    if (*mdx_start != 0x1A) {
        printf("ERROR: Missing 0x1A marker\n");
        return 1;
    }
    mdx_start++;

    while (mdx_start < p + fsize && *mdx_start != 0) mdx_start++;
    mdx_start++;

    size_t mdx_body_len = 0;
    size_t remaining = fsize - (mdx_start - p);
    uint8_t* mdx_body = decompress_if_lzx(mdx_start, remaining, mdx_body_len);
    if (!mdx_body) {
        printf("ERROR: Failed to decompress MDX body\n");
        return 1;
    }

    printf("MDX body: %zu bytes\n", mdx_body_len);

    // 44.1kHz で初期化 (より安定した再生品質)
    int sample_rate = 44100;
    printf("Initializing MXDRVG with %d Hz...\n", sample_rate);
    MXDRVG_Start(sample_rate, 0, 64 * 1024, 1024 * 1024);
    MXDRVG_TotalVolume(256);  // 最大音量設定（必須）
    printf("[DEBUG] After MXDRVG_Start: bufsize arg was 65536\n");

    MDXWrapper mdx_wrapped = wrapMDX(mdx_body, mdx_body_len, false);
    
    // SetData 前に mdx_wrapped を static に保存（MXDRVG_End による影響を避ける）
    static std::vector<uint8_t> mdx_data_persistent;
    mdx_data_persistent = mdx_wrapped.data;
    
    printf("[DEBUG] SetData: data size=%zu, ptr=%p\n", mdx_data_persistent.size(), mdx_data_persistent.data());
    MXDRVG_SetData(mdx_data_persistent.data(), mdx_data_persistent.size(), NULL, 0);
    printf("[DEBUG] After SetData\n");

    printf("[DEBUG] Skipping MeasurePlayTime, direct PlayAt\n");
    MXDRVG_PlayAt(0, 0, 1);  // 3番目パラメータ = 1 (フェードアウト ON)

    printf("Generating PCM...\n");
    FILE* out = fopen(output_path, "wb");
    if (!out) {
        printf("ERROR: Cannot create output file: %s\n", output_path);
        return 1;
    }

    // WAV ヘッダー構造体
    struct WAVHeader {
        char riff[4];
        uint32_t file_size;
        char wave[4];
        char fmt[4];
        uint32_t fmt_size;
        uint16_t format_code;
        uint16_t num_channels;
        uint32_t sample_rate;
        uint32_t byte_rate;
        uint16_t block_align;
        uint16_t bits_per_sample;
        char data[4];
        uint32_t data_size;
    } wav_header = {0};

    memcpy(wav_header.riff, "RIFF", 4);
    memcpy(wav_header.wave, "WAVE", 4);
    memcpy(wav_header.fmt, "fmt ", 4);
    memcpy(wav_header.data, "data", 4);
    wav_header.fmt_size = 16;
    wav_header.format_code = 1;  // PCM
    wav_header.num_channels = 2;
    wav_header.sample_rate = sample_rate;
    wav_header.bits_per_sample = 16;
    wav_header.block_align = (wav_header.num_channels * wav_header.bits_per_sample) / 8;
    wav_header.byte_rate = wav_header.sample_rate * wav_header.block_align;

    // ヘッダーをひとまず書き込む（後で更新）
    long header_pos = ftell(out);
    fwrite(&wav_header, sizeof(wav_header), 1, out);

    static const int FRAME_COUNT = 1024;  // MXDRVG_GetPCM のサイズ制限に合わせる（最大1024フレーム）
    int16_t pcm_buf[FRAME_COUNT * 2];

    int frames_written = 0;
    int iterations = 0;
    const int MAX_ITERATIONS = 10000;

    while (!MXDRVG_GetTerminated() && iterations < MAX_ITERATIONS) {
        int ret = MXDRVG_GetPCM(pcm_buf, FRAME_COUNT);
        
        if (ret <= 0) break;

        fwrite(pcm_buf, sizeof(int16_t), ret * 2, out);
        frames_written += ret;
        iterations++;
    }

    // WAV ヘッダーを更新（ファイルサイズ + データサイズ）
    uint32_t data_size = frames_written * 2 * sizeof(int16_t);
    uint32_t file_size = 36 + data_size;
    
    fseek(out, header_pos + 4, SEEK_SET);
    fwrite(&file_size, sizeof(uint32_t), 1, out);
    
    fseek(out, header_pos + 40, SEEK_SET);
    fwrite(&data_size, sizeof(uint32_t), 1, out);

    fclose(out);
    MXDRVG_End();
    free(mdx_body);
    free(raw_data);

    printf("WAV saved: %s (%d frames, %.1f seconds)\n", output_path, frames_written, (double)frames_written / sample_rate);

    return 0;
}
