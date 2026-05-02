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
uint32_t Operator::logsin_table_[256] = {0};
uint32_t Operator::exp_table_[256] = {0};
uint32_t Operator::eg_step_table_[64] = {0};

// Log-sine ROM (from Nuked OPM)
static const uint16_t logsin_rom[256] = {
    0x859, 0x6c3, 0x607, 0x58b, 0x52e, 0x4e4, 0x4a6, 0x471,
    0x443, 0x41a, 0x3f5, 0x3d3, 0x3b5, 0x398, 0x37e, 0x365,
    0x34e, 0x339, 0x324, 0x311, 0x2ff, 0x2ed, 0x2dc, 0x2cd,
    0x2bd, 0x2af, 0x2a0, 0x293, 0x286, 0x279, 0x26d, 0x261,
    0x256, 0x24b, 0x240, 0x236, 0x22c, 0x222, 0x218, 0x20f,
    0x206, 0x1fd, 0x1f5, 0x1ec, 0x1e4, 0x1dc, 0x1d4, 0x1cd,
    0x1c5, 0x1be, 0x1b7, 0x1b0, 0x1a9, 0x1a2, 0x19b, 0x195,
    0x18f, 0x188, 0x182, 0x17c, 0x177, 0x171, 0x16b, 0x166,
    0x160, 0x15b, 0x155, 0x150, 0x14b, 0x146, 0x141, 0x13c,
    0x137, 0x133, 0x12e, 0x129, 0x125, 0x121, 0x11c, 0x118,
    0x114, 0x10f, 0x10b, 0x107, 0x103, 0x0ff, 0x0fb, 0x0f8,
    0x0f4, 0x0f0, 0x0ec, 0x0e9, 0x0e5, 0x0e2, 0x0de, 0x0db,
    0x0d7, 0x0d4, 0x0d1, 0x0cd, 0x0ca, 0x0c7, 0x0c4, 0x0c1,
    0x0be, 0x0bb, 0x0b8, 0x0b5, 0x0b2, 0x0af, 0x0ac, 0x0a9,
    0x0a7, 0x0a4, 0x0a1, 0x09f, 0x09c, 0x099, 0x097, 0x094,
    0x092, 0x08f, 0x08d, 0x08a, 0x088, 0x086, 0x083, 0x081,
    0x07f, 0x07d, 0x07a, 0x078, 0x076, 0x074, 0x072, 0x070,
    0x06e, 0x06c, 0x06a, 0x068, 0x066, 0x064, 0x062, 0x060,
    0x05e, 0x05c, 0x05b, 0x059, 0x057, 0x055, 0x053, 0x052,
    0x050, 0x04e, 0x04d, 0x04b, 0x04a, 0x048, 0x046, 0x045,
    0x043, 0x042, 0x040, 0x03f, 0x03e, 0x03c, 0x03b, 0x039,
    0x038, 0x037, 0x035, 0x034, 0x033, 0x031, 0x030, 0x02f,
    0x02e, 0x02d, 0x02b, 0x02a, 0x029, 0x028, 0x027, 0x026,
    0x025, 0x024, 0x023, 0x022, 0x021, 0x020, 0x01f, 0x01e,
    0x01d, 0x01c, 0x01b, 0x01a, 0x019, 0x018, 0x017, 0x017,
    0x016, 0x015, 0x014, 0x014, 0x013, 0x012, 0x011, 0x011,
    0x010, 0x00f, 0x00f, 0x00e, 0x00d, 0x00d, 0x00c, 0x00c,
    0x00b, 0x00a, 0x00a, 0x009, 0x009, 0x008, 0x008, 0x007,
    0x007, 0x007, 0x006, 0x006, 0x005, 0x005, 0x005, 0x004,
    0x004, 0x004, 0x003, 0x003, 0x003, 0x002, 0x002, 0x002,
    0x002, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001,
    0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000
};

// Exp table ROM (from Nuked OPM)
static const uint16_t exp_rom[256] = {
    0x7fa, 0x7f5, 0x7ef, 0x7ea, 0x7e4, 0x7df, 0x7da, 0x7d4,
    0x7cf, 0x7c9, 0x7c4, 0x7bf, 0x7b9, 0x7b4, 0x7ae, 0x7a9,
    0x7a4, 0x79f, 0x79a, 0x794, 0x78f, 0x78a, 0x785, 0x780,
    0x77b, 0x776, 0x771, 0x76c, 0x768, 0x763, 0x75e, 0x759,
    0x755, 0x750, 0x74b, 0x746, 0x742, 0x73d, 0x738, 0x734,
    0x72f, 0x72a, 0x726, 0x721, 0x71c, 0x718, 0x713, 0x70f,
    0x70a, 0x706, 0x701, 0x6fd, 0x6f8, 0x6f4, 0x6ef, 0x6eb,
    0x6e6, 0x6e2, 0x6de, 0x6d9, 0x6d5, 0x6d0, 0x6cc, 0x6c8,
    0x6c3, 0x6bf, 0x6bb, 0x6b6, 0x6b2, 0x6ae, 0x6aa, 0x6a5,
    0x6a1, 0x69d, 0x699, 0x694, 0x690, 0x68c, 0x688, 0x684,
    0x67f, 0x67b, 0x677, 0x673, 0x66f, 0x66b, 0x667, 0x663,
    0x65f, 0x65b, 0x657, 0x653, 0x64f, 0x64b, 0x647, 0x643,
    0x63f, 0x63b, 0x637, 0x633, 0x62f, 0x62b, 0x628, 0x624,
    0x620, 0x61c, 0x618, 0x614, 0x610, 0x60c, 0x609, 0x605,
    0x601, 0x5fd, 0x5f9, 0x5f5, 0x5f1, 0x5ee, 0x5ea, 0x5e6,
    0x5e2, 0x5de, 0x5db, 0x5d7, 0x5d3, 0x5d0, 0x5cc, 0x5c8,
    0x5c5, 0x5c1, 0x5bd, 0x5ba, 0x5b6, 0x5b2, 0x5af, 0x5ab,
    0x5a8, 0x5a4, 0x5a0, 0x59d, 0x599, 0x596, 0x592, 0x58f,
    0x58b, 0x588, 0x584, 0x581, 0x57d, 0x57a, 0x576, 0x573,
    0x56f, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55b, 0x557,
    0x554, 0x551, 0x54d, 0x54a, 0x547, 0x543, 0x540, 0x53c,
    0x539, 0x536, 0x532, 0x52f, 0x52c, 0x528, 0x525, 0x522,
    0x51e, 0x51b, 0x518, 0x515, 0x511, 0x50e, 0x50b, 0x508,
    0x504, 0x501, 0x4fe, 0x4fa, 0x4f7, 0x4f4, 0x4f1, 0x4ed,
    0x4ea, 0x4e7, 0x4e4, 0x4e0, 0x4dd, 0x4da, 0x4d7, 0x4d4,
    0x4d0, 0x4cd, 0x4ca, 0x4c7, 0x4c4, 0x4c0, 0x4bd, 0x4ba,
    0x4b7, 0x4b4, 0x4b1, 0x4ae, 0x4ab, 0x4a7, 0x4a4, 0x4a1,
    0x49e, 0x49b, 0x498, 0x495, 0x492, 0x48f, 0x48c, 0x489,
    0x486, 0x483, 0x480, 0x47c, 0x479, 0x476, 0x473, 0x470,
    0x46d, 0x46a, 0x467, 0x464, 0x461, 0x45e, 0x45b, 0x458,
    0x455, 0x452, 0x44f, 0x44c, 0x449, 0x446, 0x443, 0x440
};

Operator::Operator()
    : pg_count_(0), pg_diff_(0),
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

    // ===== Log-sine table (from Nuked OPM) =====
    for (int i = 0; i < 256; i++) {
        logsin_table_[i] = logsin_rom[i];
    }

    // ===== MUL table (Frequency Multiplier) =====
    // MUL = 0 -> 0.5x, MUL = 1 -> 1x, MUL = 2 -> 2x, ..., MUL = 15 -> 15x
    for (int i = 0; i < 16; i++) {
        mul_table_[i] = (i == 0) ? (1 << 9) / 2 : (i << 9);
    }

    // ===== Exponential table (from Nuked OPM) =====
    for (int i = 0; i < 256; i++) {
        exp_table_[i] = exp_rom[i];
    }

    // ===== EG step table (rate to increment mapping) =====
    // YM2151 EG rates: 0-63 (effective rate after KS correction)
    // Formula: steps per sample ≈ 2.537 * 2^(rate-63) in 16.16 fixed-point
    // Reference: YM2151 logarithmic rate scaling
    for (int rate = 0; rate < 64; rate++) {
        if (rate == 0) {
            eg_step_table_[rate] = 0;
        } else if (rate >= 60) {
            // Very fast rates: instant attack (Nuked OPM behavior for rate 60+)
            eg_step_table_[rate] = 0x7FFFFFFF; // Effectively infinite step
        } else {
            // Calculate steps per sample in 16.16 fixed point
            double steps = 2.537 * pow(2.0, rate - 63);
            uint32_t steps_fixed = static_cast<uint32_t>(steps * 65536.0);
            if (steps_fixed == 0 && rate > 0) {
                steps_fixed = 1; // Minimum non-zero step
            }
            eg_step_table_[rate] = steps_fixed;
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
    UpdatePGDiff();
}

void Operator::SetDT2(uint8_t dt2) {
    dt2_ = dt2 & 0x03;
    UpdatePGDiff();
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
// ===== Update PG difference =====
// Nuked OPM pg_freqtable[64] and OPM_KCToFNum() based
void Operator::UpdatePGDiff() {
    // YM2151 frequency calculation using Nuked OPM reference
    // pg_freqtable[64]: basefreq, approxtype, slope for each KC high 6 bits
    
    static const struct {
        int32_t basefreq;
        int32_t approxtype;  // 1=linear, 0=log
        int32_t slope;
    } pg_freqtable[64] = {
        { 1299, 1, 19 }, { 1318, 1, 19 }, { 1337, 1, 19 }, { 1356, 1, 20 },
        { 1376, 1, 20 }, { 1396, 1, 20 }, { 1416, 1, 21 }, { 1437, 1, 20 },
        { 1458, 1, 21 }, { 1479, 1, 21 }, { 1501, 1, 22 }, { 1523, 1, 22 },
        { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 },
        { 1545, 1, 22 }, { 1567, 1, 22 }, { 1590, 1, 23 }, { 1613, 1, 23 },
        { 1637, 1, 23 }, { 1660, 1, 24 }, { 1685, 1, 24 }, { 1709, 1, 24 },
        { 1734, 1, 25 }, { 1759, 1, 25 }, { 1785, 1, 26 }, { 1811, 1, 26 },
        { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 },
        { 1837, 1, 26 }, { 1864, 1, 27 }, { 1891, 1, 27 }, { 1918, 1, 28 },
        { 1946, 1, 28 }, { 1975, 1, 28 }, { 2003, 1, 29 }, { 2032, 1, 30 },
        { 2062, 1, 30 }, { 2092, 1, 30 }, { 2122, 1, 31 }, { 2153, 1, 31 },
        { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 },
        { 2185, 1, 31 }, { 2216, 0, 31 }, { 2249, 0, 31 }, { 2281, 0, 31 },
        { 2315, 0, 31 }, { 2348, 0, 31 }, { 2382, 0, 30 }, { 2417, 0, 30 },
        { 2452, 0, 30 }, { 2488, 0, 30 }, { 2524, 0, 30 }, { 2561, 0, 30 },
        { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 }, { 0,    0, 16 }
    };
    
    // Calculate F-num from KC (Nuked OPM OPM_KCToFNum)
    int32_t kcode_h = (kc_ >> 4) & 63;
    int32_t kcode_l = kc_ & 15;
    
    int32_t sum = 0;
    if (pg_freqtable[kcode_h].approxtype) {
        // Linear interpolation
        for (int i = 0; i < 4; i++) {
            if (kcode_l & (1 << i)) {
                sum += (pg_freqtable[kcode_h].slope >> (3 - i));
            }
        }
    } else {
        // Log approximation
        int32_t slope = pg_freqtable[kcode_h].slope | 1;
        if (kcode_l & 1) sum += (slope >> 3) + 2;
        if (kcode_l & 2) sum += 8;
        if (kcode_l & 4) sum += slope >> 1;
        if (kcode_l & 8) sum += slope + 1;
        if ((kcode_l & 12) == 12 && (pg_freqtable[kcode_h].slope & 1) == 0) sum += 4;
    }
    int32_t fnum = pg_freqtable[kcode_h].basefreq + (sum >> 1);

    // Apply KF (Key Fraction) - Nuked OPM uses fnum directly
    // KF adds fine tuning: 0-63 steps per note
    if (kf_ > 0) {
        fnum += (kf_ * pg_freqtable[kcode_h].slope) >> 6;
    }

    // Apply DT2 (coarse detune in semitones): 0-3 semitones up
    // Multipliers: 2^(dt2/12) for dt2 = 0,1,2,3
    // Using fixed-point approximations (scaled to preserve precision)
    if (dt2_ > 0) {
        // DT2 semitone multipliers (fixed-point, scaled by 65536)
        static const int32_t dt2_mult[4] = { 65536, 69558, 73550, 77659 };
        fnum = (fnum * dt2_mult[dt2_]) >> 16;
    }

    // Apply block (octave): YM2151 uses 3-bit block from KC high bits
    int32_t block = (kc_ >> 4) & 7;
    int32_t basefreq = (fnum << block) >> 2;
    
    // Apply MUL (frequency multiplier)
    // MUL=0 -> 0.5x, MUL=1-15 -> 1x-15x
    int32_t mul = (mul_ == 0) ? 1 : mul_;
    int32_t inc;
    if (mul) {
        inc = basefreq * mul;
    } else {
        inc = basefreq >> 1;
    }
    inc &= 0xfffff;  // 20-bit phase increment
    
    // Apply DT1 (detune) - Nuked OPM 準拠
    if (dt1_ > 0) {
        static const int32_t pg_detune[8] = { 16, 17, 19, 20, 22, 24, 27, 29 };
        int32_t dt_l = dt1_ & 3;  // DT1 magnitude (bits 0-1)
        if (dt_l) {
            // Block-dependent detune calculation (Nuked OPM)
            int32_t kcode_adj = kc_;
            if (kcode_adj > 0x1c) kcode_adj = 0x1c;  // Clamp
            int32_t block = kcode_adj >> 2;
            int32_t note = kcode_adj & 3;
            // sum = block + 9 + extra
            // extra = 1 if dt_l==3 OR (dt_l & 2)!=0
            int32_t sum = block + 9 + ((dt_l == 3) | (dt_l & 2));
            int32_t sum_h = sum >> 1;
            int32_t sum_l = sum & 1;
            int32_t detune = pg_detune[(sum_l << 2) | note] >> (9 - sum_h);

            // Apply direction (DT1 bit 2)
            if (dt1_ & 0x04) {
                basefreq -= detune;
            } else {
                basefreq += detune;
            }
            inc = basefreq * mul;
            inc &= 0xfffff;
        }
    }
    
    // Convert to our 21-bit phase counter, sample rate 44100 Hz
    // Nuked OPM uses OPM clock (3.579545 MHz), we need to adapt
    const uint32_t OPM_CLOCK = 3579545;
    const uint32_t SAMPLE_RATE = 44100;
    pg_diff_ = ((uint64_t)inc * SAMPLE_RATE * 256) / OPM_CLOCK;
}

// ===== Update EG (Envelope Generator) =====
// Apply KS (Key Scale) correction to rate
// Nuked OPM: rate = rate * 2 + ksv, where ksv = kc >> (ks ^ 3)
static uint8_t ApplyKSToRate(uint8_t rate, uint8_t ks, uint8_t kc) {
    if (rate == 0) return 0;
    // ksv = kc >> (ks ^ 3)  (Nuked OPM reference)
    uint8_t ksv = kc >> (ks ^ 3);
    // If KS=0 and rate is 0, mask lower 2 bits
    if (ks == 0 && rate == 0) {
        ksv &= ~3;
    }
    int new_rate = rate * 2 + ksv;
    if (new_rate >= 64) new_rate = 63;
    return static_cast<uint8_t>(new_rate);
}

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
            uint8_t effective_ar = ApplyKSToRate(ar_, ks_, kc_);
            step = eg_step_table_[effective_ar];
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
            uint8_t effective_dr = ApplyKSToRate(dr_, ks_, kc_);
            step = eg_step_table_[effective_dr];
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
                uint8_t effective_sr = ApplyKSToRate(sr_, ks_, kc_);
                step = eg_step_table_[effective_sr];
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
            // YM2151: RR = rr * 2 + 1 (Nuked OPM line 554)
            uint8_t effective_rr = ApplyKSToRate(rr_ * 2 + 1, ks_, kc_);
            step = eg_step_table_[effective_rr];
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

// ===== Calculate operator output for one sample (Nuked OPM style) =====
int32_t Operator::Calculate(int32_t in, int32_t am, int32_t pm) {
    if (eg_phase_ == EGPhase::Off) {
        out_ = 0;
        return 0;
    }
    
    // Phase calculation (10-bit phase from 21-bit counter)
    uint32_t phase = (pg_count_ >> 11) & 0x3FF;
    
    // Apply pitch modulation (PM from LFO)
    if (pm != 0) {
        phase = (phase + (pm >> 9)) & 0x3FF;
    }
    
    // Apply modulation input (from feedback or previous operator)
    if (in != 0) {
        phase = (phase + (in >> 8)) & 0x3FF;
    }
    
    // Get quadrant (0-3)
    uint32_t quadrant = (phase >> 8) & 3;
    
    // Get sine index (0-255)
    uint32_t sin_idx = phase & 0xFF;
    // Reflect for quadrants 1 and 2
    if (quadrant & 1) {
        sin_idx ^= 0xFF;
    }
    
    // Log-sine lookup (10-bit value)
    uint32_t logsin_val = logsin_table_[sin_idx];
    
    // Attenuation: logsin + EG + TL
    // eg_level_: 0=loudest, 127=silent (7-bit)
    // tl_: 0=loudest, 127=silent (7-bit)
    // Shift by 3 to convert to 10-bit attenuation
    uint32_t atten = logsin_val + ((eg_level_ + tl_) << 3);
    
    // Clamp to 10 bits (0x3FF = silent)
    if (atten > 0x3FF) atten = 0x3FF;
    
    // Apply AM (LFO amplitude modulation)
    // AM adds to attenuation (makes sound quieter)
    if (am_on_ && (am != 0)) {
        int32_t am_val = am >> 16;  // am is << 16, so >> 16 gives 0-127 range
        if (am_val > 0) {
            if (atten + am_val <= 0x3FF) {
                atten += am_val;
            } else {
                atten = 0x3FF;
            }
        }
    }
    
    // Exp lookup: convert log attenuation to linear output
    uint32_t exp_val = exp_table_[atten & 0xFF];
    uint32_t shift = (atten >> 8) & 0x07;
    int32_t result = (int32_t)(exp_val << 2) >> shift;
    
    // Apply sign based on quadrant (0 and 1 are positive, 2 and 3 are negative)
    if (quadrant & 2) {
        result = -result;
    }
    
    // Output scaling: Nuked OPM outputs 14-bit
    // Mask to 14 bits (0x3FFF) and sign-extend
    result &= 0x3FFF;  // 14-bit mask
    if (result & 0x2000) result -= 0x4000;  // Sign extend from 14-bit to int32_t
    
    out_ = result;
    return result;
}

// ===== Prepare for next sample =====
void Operator::Prepare() {
    // Update phase
    pg_count_ += pg_diff_;

    // Update EG
    UpdateEG();
}

} // namespace opm
