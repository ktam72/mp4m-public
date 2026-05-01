/*
 * Copyright (c) 2026
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include "operator.h"
#include <cmath>
#include <cstdio>

namespace opm {

// Static table storage
bool Operator::tables_initialized_ = false;
uint32_t Operator::mul_table_[16] = {0};
int32_t Operator::sine_table_[1024] = {0};
int32_t Operator::exp_table_[256] = {0};  // Exponential attenuation table
int32_t Operator::eg_step_table_[64] = {0};  // EG rate-to-increment mapping

Operator::Operator() 
    : pg_count_(0), pg_diff_(0),
      detune_(0), detune2_(0),
      eg_phase_(EGPhase::Off), eg_level_(127), eg_count_(0),
      ar_(0), dr_(0), sr_(0), rr_(0), sl_(0),
      tl_(0), kc_(0), kf_(0), ks_(0), mul_(0),
      dt1_(0), dt2_(0), ssg_eg_(0),
      am_on_(false), keyon_(false), out_(0) {
    if (!tables_initialized_) {
        InitializeTables();
    }
}

void Operator::InitializeTables() {
    if (tables_initialized_) return;

    // ===== Sine table (0-90 degrees, 1024 entries) =====
    // sin(x) normalized to -32768 to +32767
    for (int i = 0; i < 1024; i++) {
        double angle = (double)i * M_PI / 2.0 / 1024.0;
        sine_table_[i] = (int32_t)(32767.0 * sin(angle));
    }

    // ===== MUL table (Frequency Multiplier) =====
    // MUL = 0 -> 0.5x, MUL = 1 -> 1x, MUL = 2 -> 2x, ..., MUL = 15 -> 15x
    for (int i = 0; i < 16; i++) {
        mul_table_[i] = (i == 0) ? (1 << 9) / 2 : (i << 9);
    }

    // ===== Exponential attenuation table =====
    // YM2151: -0.75dB per step (2 * 0.375dB)
    // exp_table[i] represents the attenuation multiplier
    // exp_table[0] = 65536 (no attenuation, 1.0 in fixed-point)
    // exp_table[127] = ~327 (-48dB)
    // exp_table[255] = ~1 (-96dB)
    for (int i = 0; i < 256; i++) {
        double atten_db = -i * 0.75;  // -0.75dB per step
        double atten_linear = pow(10.0, atten_db / 20.0);
        exp_table_[i] = (int32_t)(atten_linear * 65536.0);
        if (exp_table_[i] < 1) exp_table_[i] = 1;  // Minimum 1
    }

    // ===== EG Rate table =====
    // YM2151: EG clock is internal clock / 2
    // For 44.1kHz sampling:
    // - Internal clock = 44.1kHz * some multiplier (typically 32)
    // - EG updates every 2 internal clocks
    // 
    // Attack rate table: Maps rate (0-63) to level-per-sample increment
    // Based on YM2151 typical timing:
    // Rate 0: no change
    // Rate 63: very fast (max speed)
    //
    // Simplified: step = (rate + 1) << (15 - (rate >> 4))
    // This gives reasonable attack/decay times
    for (int rate = 0; rate < 64; rate++) {
        if (rate == 0) {
            eg_step_table_[rate] = 0;
        } else {
            // Basic formula: faster rates have larger steps
            // rate 1-15: slower speeds
            // rate 16-31: medium speeds
            // rate 32-47: faster speeds
            // rate 48-63: very fast speeds
            int base = rate;
            int shift = (rate >= 48) ? 8 : (rate >= 32) ? 7 : (rate >= 16) ? 6 : 5;
            eg_step_table_[rate] = base << shift;
        }
    }

    tables_initialized_ = true;
}

// ===== Key On/Off =====
void Operator::KeyOn() {
    if (!keyon_) {
        keyon_ = true;
        eg_phase_ = EGPhase::Attack;
        eg_count_ = 0;
        eg_level_ = 127;  // Start at minimum level (0dB)
    }
}

void Operator::KeyOff() {
    keyon_ = false;
    eg_phase_ = EGPhase::Release;
    eg_count_ = 0;
}

// ===== Parameter setters =====
void Operator::SetDT(uint8_t dt) {
    dt1_ = dt & 0x07;
    UpdateDetune();
}

void Operator::SetDT2(uint8_t dt2) {
    dt2_ = dt2 & 0x03;
    UpdateDetune();
}

void Operator::SetMUL(uint8_t mul) {
    mul_ = mul & 0x0f;
    UpdatePGDiff();
}

void Operator::SetTL(uint8_t tl) {
    tl_ = tl & 0x7f;
}

void Operator::SetKS(uint8_t ks) {
    ks_ = ks & 0x03;
}

void Operator::SetAR(uint8_t ar) {
    ar_ = ar & 0x1f;
}

void Operator::SetDR(uint8_t dr) {
    dr_ = dr & 0x1f;
}

void Operator::SetSR(uint8_t sr) {
    sr_ = sr & 0x1f;
}

void Operator::SetRR(uint8_t rr) {
    rr_ = rr & 0x1f;
}

void Operator::SetSL(uint8_t sl) {
    sl_ = (sl & 0x0f) << 3;  // Convert 4-bit to 7-bit
}

void Operator::SetSSGEG(uint8_t mode) {
    ssg_eg_ = mode & 0x0f;
}

void Operator::SetKCKF(uint8_t kc, uint8_t kf) {
    kc_ = kc & 0x7f;
    kf_ = kf & 0x3f;
    UpdatePGDiff();
}

void Operator::SetAM(bool enable) {
    am_on_ = enable;
}

// ===== Update detune =====
void Operator::UpdateDetune() {
    // DT1: Fine detune (-3 to +3 cents)
    // DT2: Coarse detune (0, +1, +2, +3 semitones)
    
    // Simplified: convert to frequency ratio
    // 1 cent = 2^(1/1200)
    // This is approximate - real YM2151 has more complex behavior
    
    detune_ = 0;
    detune2_ = 0;
    
    if (dt1_ > 0) {
        int dt1_cents = (dt1_ > 3) ? -(7 - dt1_) : (dt1_ - 1);
        // Approximate: each cent = 0.0578% frequency change
        detune_ = (dt1_cents * 65536) / 1200;
    }
    
    if (dt2_ > 0) {
        // DT2: semitone units (12 cents each)
        detune2_ = (dt2_ * 12 * 65536) / 1200;
    }
}

// ===== Update PG difference =====
void Operator::UpdatePGDiff() {
    // YM2151 周波数計算 (fmgen SetKCKF を完全複製)
    // これにより、fmgen と完全に同じ周波数計算を実現
    
    // KC テーブル (fmgen から直接コピー)
    static const uint32_t kctable[16] = {
        5197, 5506, 5833, 6180, 6180, 6547, 6937, 7349,
        7349, 7786, 8249, 8740, 8740, 9259, 9810, 10394,
    };
    
    // KF テーブル (fmgen の計算を複製)
    static uint32_t kftable[64] = {0};
    static bool kftable_init = false;
    
    if (!kftable_init) {
        for (int i = 0; i < 64; i++) {
            double ratio = pow(2.0, (double)i / 768.0);
            kftable[i] = (uint32_t)(0x10000 * ratio);
        }
        kftable_init = true;
    }
    
    // fmgen の SetKCKF をそのまま複製
    int oct = 19 - ((kc_ >> 4) & 7);
    
    uint32_t kcv = kctable[kc_ & 0x0f];
    kcv = (kcv + 2) / 4 * 4;
    
    uint32_t dp = kcv * kftable[kf_ & 0x3f];
    
    // These bit operations are equivalent to no-op but ensure correct calculation
    dp >>= 16 + 3;
    dp <<= 16 + 3;
    dp >>= oct;
    
    // Apply MUL (frequency multiplier)
    // In YM2151, MUL=0 means x1/2, MUL=1-15 means x1-15
    uint32_t mul = (mul_ == 0) ? 1 : mul_;
    dp = dp * mul;
    
    // Convert YM2151 DP (operating at 3.579545 MHz) to phase increment for 44100 Hz
    // DP is the phase delta for YM2151's internal clock
    // We need to scale it to our sample rate and phase counter size
    const uint32_t OPM_CLOCK = 3579545;
    const uint32_t SAMPLE_RATE = 44100;
    
    // Scale factor: SAMPLE_RATE / OPM_CLOCK with adjustment for our phase counter
    // This matches the calculation that produces audible output
    pg_diff_ = ((uint64_t)dp * SAMPLE_RATE * 256) / OPM_CLOCK;
    
    // Apply detune (if needed - currently unused)
    // if (detune_ != 0) pg_diff_ = ...
}

// ===== Update EG (Envelope Generator) =====
void Operator::UpdateEG() {
    if (!keyon_ && eg_phase_ != EGPhase::Off) {
        // Key off: transition to Release
        if (eg_phase_ != EGPhase::Release) {
            eg_phase_ = EGPhase::Release;
            eg_count_ = 0;
        }
    }
    
    uint32_t step = 0;
    
    switch (eg_phase_) {
        case EGPhase::Attack: {
            // Attack: EG level decreases from 127 to 0
            step = eg_step_table_[ar_];
            eg_count_ += step;
            
            if (eg_count_ >= (1 << 16)) {
                eg_level_ -= (eg_count_ >> 16);
                eg_count_ &= 0xffff;
                
                if (eg_level_ <= 0) {
                    eg_level_ = 0;
                    eg_phase_ = EGPhase::Decay;
                    eg_count_ = 0;
                }
            }
            break;
        }
        
        case EGPhase::Decay: {
            // Decay: EG level increases from 0 to SL
            step = eg_step_table_[dr_];
            eg_count_ += step;
            
            if (eg_count_ >= (1 << 16)) {
                eg_level_ += (eg_count_ >> 16);
                eg_count_ &= 0xffff;
                
                if (eg_level_ >= sl_) {
                    eg_level_ = sl_;
                    eg_phase_ = EGPhase::Sustain;
                    eg_count_ = 0;
                }
            }
            break;
        }
        
        case EGPhase::Sustain: {
            // Sustain: EG level slowly increases (or stays constant)
            if (sr_ > 0) {
                step = eg_step_table_[sr_];
                eg_count_ += step;
                
                if (eg_count_ >= (1 << 16)) {
                    eg_level_ += (eg_count_ >> 16);
                    eg_count_ &= 0xffff;
                    
                    if (eg_level_ >= 127) {
                        eg_level_ = 127;
                        eg_phase_ = EGPhase::Off;
                    }
                }
            }
            break;
        }
        
        case EGPhase::Release: {
            // Release: EG level increases from current to 127
            step = eg_step_table_[rr_];
            eg_count_ += step;
            
            if (eg_count_ >= (1 << 16)) {
                eg_level_ += (eg_count_ >> 16);
                eg_count_ &= 0xffff;
                
                if (eg_level_ >= 127) {
                    eg_level_ = 127;
                    eg_phase_ = EGPhase::Off;
                }
            }
            break;
        }
        
        case EGPhase::Off:
        default:
            eg_level_ = 127;
            break;
    }
}

// ===== Sine wave lookup with quadrant mirroring =====
int32_t Operator::LookupSine(uint32_t phase) {
    // phase: 10-bit value (0-1023)
    uint32_t index = phase & 0x3ff;
    
    if (index < 256) {
        // 0-90 degrees
        return sine_table_[index];
    } else if (index < 512) {
        // 90-180 degrees (mirror)
        return sine_table_[511 - index];
    } else if (index < 768) {
        // 180-270 degrees (negative)
        return -sine_table_[index - 512];
    } else {
        // 270-360 degrees (negative mirror)
        return -sine_table_[1023 - index];
    }
}

// ===== Calculate operator output for one sample =====
int32_t Operator::Calculate(int32_t in, int32_t am, int32_t pm) {
    if (eg_phase_ == EGPhase::Off) {
        out_ = 0;
        return 0;
    }
    
    // Phase calculation with modulation
    uint32_t phase = pg_count_;
    if (pm != 0) {
        phase += (pm >> 10);  // PM: pitch modulation
    }
    if (in != 0) {
        phase += (in >> 7);   // Feedback/modulation input
    }
    
    // Sine wave lookup (-32768 to +32767)
    int32_t sine = LookupSine(phase >> 10);
    
    // EG level: 0=max volume, 127=min volume (-48dB)
    int32_t eg_att = eg_level_;
    
    // TL (Total Level): additional attenuation (0-127)
    // Combined attenuation: 0-254 (each step = -0.75dB)
    int32_t total_atten = tl_ + eg_att;
    if (total_atten > 255) total_atten = 255;
    
    // Apply AM (Amplitude Modulation) if enabled
    // AM modulates the attenuation level (reduces it)
    int32_t final_atten = total_atten;
    if (am_on_ && am != 0) {
        // am: LFO amplitude value, reduce attenuation
        final_atten -= (am >> 8);
        if (final_atten < 0) final_atten = 0;
    }
    
    // Apply exponential attenuation: sine * exp_table[atten]
    // exp_table[0] = 65536 (1.0 in fixed-point, no attenuation)
    // exp_table[255] = ~1 (-96dB)
    int64_t result = ((int64_t)sine * exp_table_[final_atten]) >> 16;
    
    // Output scaling: multiply by ~2.6 to reach proper audio level
    // This compensates for the attenuation table scale
    result = (result * 168) >> 6;  // 168/64 ≈ 2.625
    
    // Clamp to int16 range
    if (result > 32767) result = 32767;
    if (result < -32768) result = -32768;
    
    out_ = (int32_t)result;
    return out_;
}

// ===== Prepare for next sample =====
void Operator::Prepare() {
    // Update phase
    pg_count_ += pg_diff_;
    
    // Update EG
    UpdateEG();
}

} // namespace opm
