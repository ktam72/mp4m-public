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
                 am_value_(0), pm_value_(0) {
    if (!tables_initialized_) {
        InitializeTables();
    }
}

void LFO::InitializeTables() {
    if (tables_initialized_) return;

    // Initialize LFO frequency table
    // LFO frequency = (clock/64) * (2^(N-1)) / (2^20) where N = LFO freq register
    // Simplified approximation
    for (int i = 0; i < 32; i++) {
        freq_table_[i] = (i == 0) ? 0 : (1 << (i - 1)) * 10;
    }

    // Initialize waveform tables (256 entries per waveform)
    for (int i = 0; i < 256; i++) {
        // Saw: 0 -> 255 linearly
        am_saw_table_[i] = static_cast<uint8_t>(i);
        pm_saw_table_[i] = (i - 128) * (1 << 16) / 128;

        // Square: 0-127 = 255, 128-255 = 0
        am_saw_table_[i] = (i < 128) ? 255 : 0;
        pm_square_table_[i] = (i < 128) ? (1 << 23) : -(1 << 23);

        // Triangle: 0-127 up, 128-255 down
        int tri = (i < 128) ? (i * 2) : ((255 - i) * 2);
        am_triangle_table_[i] = static_cast<uint8_t>(tri);
        pm_triangle_table_[i] = (tri - 128) * (1 << 16) / 128;

        // Noise (pseudo)
        am_noise_table_[i] = static_cast<uint8_t>((i * 13) & 0xFF);
        pm_noise_table_[i] = ((i * 13) & 0xFF) - 128;
    }

    tables_initialized_ = true;
}

void LFO::SetFrequency(uint8_t freq) {
    // freq is 5 bits from register 0x18
    uint8_t f = freq & 0x1F;
    phase_increment_ = freq_table_[f];
}

void LFO::SetWaveform(LfoWave wave) {
    waveform_ = wave;
    UpdateOutput();
}

void LFO::Reset() {
    phase_ = 0;
    am_value_ = 0;
    pm_value_ = 0;
}

void LFO::Advance(int samples) {
    phase_ += phase_increment_ * samples;
    phase_ &= 0x1FFFF; // 17-bit phase (approx)
    UpdateOutput();
}

void LFO::UpdateOutput() {
    // Get table index (8-bit from phase)
    uint8_t idx = (phase_ >> 9) & 0xFF;

    switch (waveform_) {
        case LfoWave::Saw:
            am_value_ = am_saw_table_[idx];
            pm_value_ = pm_saw_table_[idx];
            break;
        case LfoWave::Square:
            am_value_ = am_square_table_[idx];
            pm_value_ = pm_square_table_[idx];
            break;
        case LfoWave::Triangle:
            am_value_ = am_triangle_table_[idx];
            pm_value_ = pm_triangle_table_[idx];
            break;
        case LfoWave::Noise:
            am_value_ = am_noise_table_[idx];
            pm_value_ = pm_noise_table_[idx];
            break;
    }
}

} // namespace opm
