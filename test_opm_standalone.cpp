/*
 * OPM Standalone Test
 * 単一オペレータで A4 (440Hz) を生成するテスト
 */

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <cstring>
#include "Vendor/opm/operator.h"

// WAV ファイル出力用の構造体
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
};

int main() {
    const int SAMPLE_RATE = 44100;
    const int DURATION_SECONDS = 2;
    const int NUM_SAMPLES = SAMPLE_RATE * DURATION_SECONDS;
    
    printf("OPM Standalone Test: A4 (440Hz) Generation\n");
    printf("Sample Rate: %d Hz\n", SAMPLE_RATE);
    printf("Duration: %d seconds\n", DURATION_SECONDS);
    printf("Total Samples: %d\n\n", NUM_SAMPLES);
    
    // OPM オペレータの作成
    opm::Operator op;
    
    // ===== パラメータ設定 =====
    printf("Setting operator parameters...\n");
    
    // A4 = 440Hz に対応するパラメータ
    // KC (Key Code) = 57: A note, octave 3
    // KF (Key Fraction) = 32: 中央
    op.SetKCKF(57, 32);
    printf("  KC=57, KF=32 (A4, 440Hz)\n");
    
    // Frequency Multiplier = 1x
    op.SetMUL(1);
    printf("  MUL=1 (1x frequency)\n");
    
    // Total Level = 0 (no attenuation, max volume)
    op.SetTL(0);
    printf("  TL=0 (max volume)\n");
    
    // Envelope parameters (ADSR)
    // AR (Attack Rate) = 31 (fast attack, ~2ms)
    op.SetAR(31);
    
    // DR (Decay Rate) = 15 (medium decay)
    op.SetDR(15);
    
    // SR (Sustain Rate) = 0 (no sustain decay)
    op.SetSR(0);
    
    // SL (Sustain Level) = 0 (sustain at full volume)
    op.SetSL(0);
    
    // RR (Release Rate) = 7 (medium release)
    op.SetRR(7);
    
    printf("  AR=31, DR=15, SR=0, SL=0, RR=7\n");
    
    // Detune = 0 (no detune)
    op.SetDT(0);
    op.SetDT2(0);
    printf("  DT=0, DT2=0 (no detune)\n");
    
    // No AM
    op.SetAM(false);
    printf("  AM disabled\n");
    
    // ===== オーディオ生成 =====
    printf("\nGenerating audio...\n");
    
    int16_t *samples = new int16_t[NUM_SAMPLES];
    
    // Key on at sample 0
    op.KeyOn();
    printf("  Key ON at sample 0\n");
    
    // Key off at 1.5 seconds
    int keyoff_sample = SAMPLE_RATE * 15 / 10;
    printf("  Key OFF at sample %d (1.5 seconds)\n", keyoff_sample);
    
    for (int i = 0; i < NUM_SAMPLES; i++) {
        if (i == keyoff_sample) {
            op.KeyOff();
        }
        
        // Calculate: no modulation, no AM, no PM
        int32_t out = op.Calculate(0, 0, 0);
        
        // Prepare for next sample
        op.Prepare();
        
        // Convert to int16
        // out は -32768 to +32767 の範囲のはず
        samples[i] = (int16_t)out;
        
        // ログ: 最初と最後の数サンプルを出力
        if (i < 5 || i >= NUM_SAMPLES - 5) {
            printf("  Sample %d: %d\n", i, samples[i]);
        } else if (i == 5) {
            printf("  ...\n");
        }
    }
    
    printf("Audio generation complete.\n\n");
    
    // ===== WAV ファイル出力 =====
    printf("Writing WAV file...\n");
    
    FILE *f = fopen("/tmp/test_opm_standalone.wav", "wb");
    if (!f) {
        printf("ERROR: Cannot open output file\n");
        return 1;
    }
    
    // WAV ヘッダー作成
    WAVHeader hdr = {};
    memcpy(hdr.riff, "RIFF", 4);
    memcpy(hdr.wave, "WAVE", 4);
    memcpy(hdr.fmt, "fmt ", 4);
    memcpy(hdr.data, "data", 4);
    
    hdr.fmt_size = 16;
    hdr.format_code = 1;  // PCM
    hdr.num_channels = 1; // Mono
    hdr.sample_rate = SAMPLE_RATE;
    hdr.bits_per_sample = 16;
    hdr.block_align = (hdr.num_channels * hdr.bits_per_sample) / 8;
    hdr.byte_rate = hdr.sample_rate * hdr.block_align;
    hdr.data_size = NUM_SAMPLES * sizeof(int16_t);
    hdr.file_size = 36 + hdr.data_size;
    
    // ヘッダー書き込み
    fwrite(&hdr, sizeof(WAVHeader), 1, f);
    
    // サンプルデータ書き込み
    fwrite(samples, sizeof(int16_t), NUM_SAMPLES, f);
    
    fclose(f);
    printf("WAV file written: /tmp/test_opm_standalone.wav\n");
    printf("File size: %u bytes\n", (unsigned)(36 + hdr.data_size));
    
    // クリーンアップ
    delete[] samples;
    
    printf("\n✓ Test complete. Play with: afplay /tmp/test_opm_standalone.wav\n");
    
    return 0;
}
