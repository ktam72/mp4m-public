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

    // Set LFO PMD (Pitch Modulation Depth, from register 0x19 bit 7=1)
    void SetPMD(uint8_t pmd) { pmd_ = pmd & 0x7F; }

    // Set LFO AMD (Amplitude Modulation Depth, from register 0x19 bit 7=0)
    void SetAMD(uint8_t amd) { amd_ = amd & 0x7F; }

    // Get PMD/AMD values (for channel-level scaling)
    uint8_t GetPMD() const { return pmd_; }
    uint8_t GetAMD() const { return amd_; }

    // Reset LFO
    void Reset();

    // Advance by one sample
    void Advance(int samples = 1);

    // Get LFO values (raw, before PMS/AMS scaling)
    // Returns: raw AM value (0-255)
    uint8_t GetRawAM() const { return raw_am_; }

    // Returns: raw PM value (signed)
    int32_t GetRawPM() const { return raw_pm_; }

    // Get scaled AM value (after AMD application, before channel AMS)
    uint8_t GetAM() const { return am_value_; }

    // Get scaled PM value (after PMD application, before channel PMS)
    int32_t GetPM() const { return pm_value_; }

    // Initialize LFO tables
    static void InitializeTables();

private:
    // LFO phase accumulator
    uint32_t phase_;
    uint32_t phase_increment_;

    // LFO waveform
    LfoWave waveform_;

    // LFO depth settings (from register 0x19)
    uint8_t pmd_;  // Pitch Modulation Depth (0-127)
    uint8_t amd_;  // Amplitude Modulation Depth (0-127)

    // Current raw output values (before PMD/AMD scaling)
    uint8_t raw_am_;
    int32_t raw_pm_;

    // Current scaled output values (after PMD/AMD, before channel PMS/AMS)
    uint8_t am_value_;
    int32_t pm_value_;

    // Nuked OPM形式のカウンター（周期制御用）
    uint8_t counter1_;           // 4-bit counter
    uint16_t counter2_;          // 16-bit accumulator
    uint16_t counter3_;          // wave phase counter

    uint8_t counter1_of1_;       // counter1 overflow tracking (2-bit shift register)
    uint8_t counter2_of_;        // counter2 bit 15 overflow
    uint8_t counter3_clock_;     // clock signal to counter3
    uint8_t counter2_load_;      // load signal to counter2

    // Frequency parameters
    uint8_t lfo_freq_hi_;        // lfo_freq >> 1 (for counter2_table index)
    uint8_t lfo_freq_lo_;        // lfo_freq & 0x0F (for counter3 detail)

    // LFO frequency table (32 entries, indexed by LFO freq register)
    static uint32_t freq_table_[32];

    // Counter2 table (16 entries for period control) - Nuked OPM
    static const uint16_t counter2_table_[16];

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
