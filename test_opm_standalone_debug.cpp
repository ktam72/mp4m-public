/*
 * OPM Standalone Test with Debug Logging
 */

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <cstring>
#include "Vendor/opm/operator.h"

int main() {
    const int SAMPLE_RATE = 44100;
    
    printf("OPM Standalone Debug Test\n");
    printf("Sample Rate: %d Hz\n\n", SAMPLE_RATE);
    
    // OPM オペレータの作成
    opm::Operator op;
    
    printf("=== Parameter Setup ===\n");
    
    // A4 パラメータ
    op.SetKCKF(57, 32);
    printf("✓ SetKCKF(57, 32) called\n");
    
    op.SetMUL(1);
    printf("✓ SetMUL(1) called\n");
    
    op.SetTL(0);
    printf("✓ SetTL(0) called\n");
    
    op.SetAR(31);
    op.SetDR(15);
    op.SetSR(0);
    op.SetSL(0);
    op.SetRR(7);
    printf("✓ EG parameters set (AR=31, DR=15, SR=0, SL=0, RR=7)\n");
    
    op.SetDT(0);
    op.SetDT2(0);
    printf("✓ Detune disabled\n");
    
    op.SetAM(false);
    printf("✓ AM disabled\n");
    
    printf("\n=== Key On & Generate Samples ===\n");
    
    op.KeyOn();
    printf("✓ KeyOn() called\n");
    
    // 最初の 100 サンプル（約 2.3ms）を詳細にログ
    printf("\nFirst 100 samples:\n");
    for (int i = 0; i < 100; i++) {
        int32_t out = op.Calculate(0, 0, 0);
        op.Prepare();
        
        if (i < 50 || i >= 95) {
            printf("  Sample %3d: output = %6d (0x%08x)\n", i, (int)out, (unsigned)out);
        } else if (i == 50) {
            printf("  ...\n");
        }
    }
    
    printf("\n=== Analysis ===\n");
    
    // 再度実行して統計を取る
    int max_val = 0;
    int min_val = 0;
    int nonzero_count = 0;
    
    op.KeyOn();
    for (int i = 0; i < 44100; i++) {
        int32_t out = op.Calculate(0, 0, 0);
        op.Prepare();
        
        if (out != 0) nonzero_count++;
        if (out > max_val) max_val = out;
        if (out < min_val) min_val = out;
    }
    
    printf("Max output: %d\n", max_val);
    printf("Min output: %d\n", min_val);
    printf("Non-zero samples: %d / 44100 (%.1f%%)\n", nonzero_count, (double)nonzero_count / 441.0);
    
    if (max_val == 0 && min_val == 0) {
        printf("\n⚠ ERROR: All output is zero!\n");
        printf("  Possible causes:\n");
        printf("  1. Sine table not initialized\n");
        printf("  2. EG level stuck at 127 (Off phase)\n");
        printf("  3. Output calculation broken\n");
        printf("  4. PG (phase generator) not working\n");
    } else {
        printf("\n✓ Output range looks reasonable\n");
    }
    
    printf("\n=== Output Sample to WAV ===\n");
    
    // WAV 出力
    FILE *f = fopen("/tmp/test_opm_debug.wav", "wb");
    if (f) {
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
        } hdr = {};
        
        memcpy(hdr.riff, "RIFF", 4);
        memcpy(hdr.wave, "WAVE", 4);
        memcpy(hdr.fmt, "fmt ", 4);
        memcpy(hdr.data, "data", 4);
        
        hdr.fmt_size = 16;
        hdr.format_code = 1;
        hdr.num_channels = 1;
        hdr.sample_rate = SAMPLE_RATE;
        hdr.bits_per_sample = 16;
        hdr.block_align = 2;
        hdr.byte_rate = SAMPLE_RATE * 2;
        hdr.data_size = 44100 * 2;
        hdr.file_size = 36 + hdr.data_size;
        
        fwrite(&hdr, sizeof(hdr), 1, f);
        
        op.KeyOn();
        for (int i = 0; i < 44100; i++) {
            int32_t out = op.Calculate(0, 0, 0);
            op.Prepare();
            
            int16_t sample = (int16_t)out;
            fwrite(&sample, sizeof(int16_t), 1, f);
        }
        
        fclose(f);
        printf("✓ WAV written to /tmp/test_opm_debug.wav\n");
    }
    
    return 0;
}
