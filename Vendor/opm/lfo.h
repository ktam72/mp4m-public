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

#ifndef OPM_LFO_H
#define OPM_LFO_H

#include <cstdint>

namespace opm {

// LFO waveform types
enum class LfoWave {
    Saw,
    Square,
    Triangle,
    Noise
};

// LFO (Low Frequency Oscillator) class
class LFO {
public:
    LFO();

    // Set LFO frequency (from register 0x18)
    // freq: 5-bit frequency value
    void SetFrequency(uint8_t freq);

    // Set LFO waveform (from register 0x1B, bits 1-0)
    void SetWaveform(LfoWave wave);

    // Reset LFO
    void Reset();

    // Advance by one sample
    void Advance(int samples = 1);

    // Get LFO values
    // Returns: AM value (0-255)
    uint8_t GetAM() const { return am_value_; }

    // Returns: PM value (signed, in phase increment units)
    int32_t GetPM() const { return pm_value_; }

    // Initialize LFO tables
    static void InitializeTables();

private:
    // LFO phase accumulator
    uint32_t phase_;
    uint32_t phase_increment_;

    // LFO waveform
    LfoWave waveform_;

    // Current output values
    uint8_t am_value_;
    int32_t pm_value_;

    // LFO frequency table (32 entries, indexed by LFO freq register)
    static uint32_t freq_table_[32];

    // LFO waveform tables (256 entries each)
    static uint8_t am_saw_table_[256];
    static uint8_t am_square_table_[256];
    static uint8_t am_triangle_table_[256];
    static uint8_t am_noise_table_[256];

    static int32_t pm_saw_table_[256];
    static int32_t pm_square_table_[256];
    static int32_t pm_triangle_table_[256];
    static int32_t pm_noise_table_[256];

    static bool tables_initialized_;

    // Update output values based on current phase
    void UpdateOutput();
};

} // namespace opm

#endif // OPM_LFO_H
