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

#include "lfo.h"
#include <cmath>

namespace opm {

// Static table storage
uint32_t LFO::freq_table_[32] = {0};

// Counter2 table for period control (Nuked OPM)
const uint16_t LFO::counter2_table_[16] = {
    0x0000, 0x4000, 0x6000, 0x7000,
    0x7800, 0x7c00, 0x7e00, 0x7f00,
    0x7f80, 0x7fc0, 0x7fe0, 0x7ff0,
    0x7ff8, 0x7ffc, 0x7ffe, 0x7fff
};

uint8_t LFO::am_saw_table_[256] = {0};
uint8_t LFO::am_square_table_[256] = {0};
uint8_t LFO::am_triangle_table_[256] = {0};
uint8_t LFO::am_noise_table_[256] = {0};
int32_t LFO::pm_saw_table_[256] = {0};
int32_t LFO::pm_square_table_[256] = {0};
int32_t LFO::pm_triangle_table_[256] = {0};
int32_t LFO::pm_noise_table_[256] = {0};
bool LFO::tables_initialized_ = false;

LFO::LFO() : phase_(0), phase_increment_(0),
                 waveform_(LfoWave::Saw),
                 pmd_(0), amd_(0),
                 raw_am_(0), raw_pm_(0), am_value_(0), pm_value_(0) {
    if (!tables_initialized_) {
        InitializeTables();
    }
}

void LFO::InitializeTables() {
    if (tables_initialized_) return;

    // LFO frequency table (from Nuked OPM reference)
    static const uint32_t lfo_freqtable[32] = {
        0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000,
        0x001, 0x001, 0x001, 0x001, 0x002, 0x002, 0x002, 0x003,
        0x003, 0x004, 0x004, 0x005, 0x006, 0x007, 0x008, 0x009,
        0x00B, 0x00D, 0x010, 0x013, 0x017, 0x01B, 0x020, 0x025,
    };
    for (int i = 0; i < 32; i++) {
        freq_table_[i] = lfo_freqtable[i];
    }

    // Initialize waveform tables (256 entries per waveform)
    for (int i = 0; i < 256; i++) {
        // Saw: 0 -> 255 linearly
        am_saw_table_[i] = static_cast<uint8_t>(i);
        // PM from saw: signed value, range -1 to +1 (shifted for calculation)
        pm_saw_table_[i] = static_cast<int32_t>(i - 128) * (1 << 16) / 128;

        // Square: 0-127 = 255, 128-255 = 0
        am_square_table_[i] = (i < 128) ? 255 : 0;
        pm_square_table_[i] = (i < 128) ? (1 << 23) : -(1 << 23);

        // Triangle: 0-127 up, 128-255 down
        int tri = (i < 128) ? (i * 2) : ((255 - i) * 2);
        am_triangle_table_[i] = static_cast<uint8_t>(tri);
        pm_triangle_table_[i] = static_cast<int32_t>(tri - 128) * (1 << 16) / 128;

        // Noise (pseudo-random)
        am_noise_table_[i] = static_cast<uint8_t>((i * 13 + 7) & 0xFF);
        pm_noise_table_[i] = static_cast<int32_t>((i * 13 + 7) & 0xFF) - 128;
    }

    tables_initialized_ = true;
}

void LFO::SetFrequency(uint8_t freq) {
    // freq is 5 bits from register 0x18
    uint8_t f = freq & 0x1F;

    // Split into hi/lo for counter2/counter3 control
    lfo_freq_hi_ = f >> 1;    // upper 4 bits (0-15) → counter2_table index
    lfo_freq_lo_ = f & 0x0F;  // lower bits (0-15) → counter3 detail control

    // Load counter2 from table on next Advance
    counter2_load_ = 1;

    // Legacy: also set phase_increment for compatibility
    phase_increment_ = freq_table_[f];
}

void LFO::SetWaveform(LfoWave wave) {
    waveform_ = wave;
    UpdateOutput();
}

void LFO::Reset() {
    phase_ = 0;
    raw_am_ = 0;
    raw_pm_ = 0;
    am_value_ = 0;
    pm_value_ = 0;

    // Reset Nuked OPM counters
    counter1_ = 0;
    counter2_ = 0;
    counter3_ = 0;
    counter1_of1_ = 0;
    counter2_of_ = 0;
    counter3_clock_ = 0;
    counter2_load_ = 1;  // Load table on first cycle

    // Reset frequency parameters
    lfo_freq_hi_ = 0;
    lfo_freq_lo_ = 0;
}

void LFO::Advance(int samples) {
    // Nuked OPM形式のカウンター更新（サンプル単位）
    for (int s = 0; s < samples; s++) {
        // === Counter1 Logic ===
        // Counter1: 4-bit counter (0-15)
        // Advance counter1 each sample
        counter1_++;
        if (counter1_ > 15) {
            counter1_ &= 15;
            counter1_of1_ = (counter1_of1_ << 1) | 1;  // overflow
        } else {
            counter1_of1_ = (counter1_of1_ << 1) | 0;
        }
        counter1_of1_ &= 0x03;  // Keep 2-bit history

        // === Counter2 Logic ===
        // Counter2: 16-bit accumulator with overflow detection
        // counter1_of2 = (counter1_ == 2) triggers counter2 update
        uint8_t counter1_of2 = (counter1_ == 2) ? 1 : 0;

        if (counter1_of2 || counter2_load_) {
            uint16_t c2 = counter2_;

            // Add counter1 overflow if applicable
            if (counter1_of2) {
                c2 += (counter1_of1_ & 2) ? 1 : 0;
            }

            // Load from table if load signal is set
            if (counter2_load_) {
                if (lfo_freq_hi_ < 16) {
                    c2 = counter2_table_[lfo_freq_hi_];
                }
                counter2_load_ = 0;
            }

            // Detect overflow at bit 15
            counter2_of_ = (c2 >> 15) & 1;
            counter2_ = c2 & 0x7FFF;  // 15-bit mask
        }

        // === Counter3 Logic ===
        // Counter3 is advanced when counter2 overflows
        if (counter2_of_) {
            counter3_clock_ = 1;
            counter3_ += 1;
            counter3_ &= 0xFFFF;
        } else {
            counter3_clock_ = 0;
        }

        // === Phase Update ===
        // Use counter3 as phase accumulator (rough approximation)
        // counter3 value determines wave table index
        phase_ += counter3_clock_ ? 256 : 0;
        phase_ &= 0x1FFFF;  // 17-bit phase
    }

    UpdateOutput();
}

void LFO::UpdateOutput() {
    // Get table index (8-bit from phase)
    uint8_t idx = (phase_ >> 9) & 0xFF;

    // Get raw values
    switch (waveform_) {
        case LfoWave::Saw:
            raw_am_ = am_saw_table_[idx];
            raw_pm_ = pm_saw_table_[idx];
            break;
        case LfoWave::Square:
            raw_am_ = am_square_table_[idx];
            raw_pm_ = pm_square_table_[idx];
            break;
        case LfoWave::Triangle:
            raw_am_ = am_triangle_table_[idx];
            raw_pm_ = pm_triangle_table_[idx];
            break;
        case LfoWave::Noise:
            raw_am_ = am_noise_table_[idx];
            raw_pm_ = pm_noise_table_[idx];
            break;
    }

    // Apply global PMD/AMD scaling (channel PMS/AMS applied at channel level)
    // AM: raw_am_ (0-255) * amd_ (0-127) / 128
    am_value_ = (raw_am_ * amd_) / 128;
    if (am_value_ > 255) am_value_ = 255;

    // PM: raw_pm_ * pmd_ / 128
    pm_value_ = raw_pm_ * pmd_ / 128;
}

// GetAM() and GetPM() now return pre-scaled values from UpdateOutput()
// Channel-level PMS/AMS scaling is applied in channel.cpp

} // namespace opm
