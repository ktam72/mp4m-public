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

#ifndef OPM_OPERATOR_H
#define OPM_OPERATOR_H

#include <cstdint>
#include <cstddef>

namespace opm {

// Envelope Generator phases
enum class EGPhase {
    Off,
    Attack,
    Decay,
    Sustain,
    Release
};

// Operator class - implements a single FM operator
class Operator {
public:
    Operator();

    // Key on/off
    void KeyOn();
    void KeyOff();

    // Parameter setters (from OPM registers)
    void SetDT(uint8_t dt);      // Detune 1
    void SetDT2(uint8_t dt2);    // Detune 2
    void SetMUL(uint8_t mul);    // Frequency Multiplier
    void SetTL(uint8_t tl);      // Total Level
    void SetKS(uint8_t ks);      // Key Scale
    void SetAR(uint8_t ar);      // Attack Rate
    void SetDR(uint8_t dr);      // Decay Rate
    void SetSR(uint8_t sr);      // Sustain Rate
    void SetRR(uint8_t rr);      // Release Rate
    void SetSL(uint8_t sl);      // Sustain Level
    void SetSSGEG(uint8_t mode); // SSG-EG mode (unused currently)

    // Set frequency (KC=Key Code, KF=Key Fraction)
    void SetKCKF(uint8_t kc, uint8_t kf);

    // Enable/disable Amplitude Modulation
    void SetAM(bool enable);

    // Calculate operator output for one sample
    // in: feedback/modulation input
    // am: LFO amplitude modulation value
    // pm: LFO pitch modulation value
    // Returns: operator output (int32_t)
    int32_t Calculate(int32_t in, int32_t am, int32_t pm);

    // Update internal state for next sample
    // Must be called once per sample (after Calculate)
    void Prepare();

    // Check if operator is active
    bool IsActive() const { return eg_phase_ != EGPhase::Off; }

    // Check if operator is key on
    bool IsKeyOn() const { return eg_phase_ != EGPhase::Off && eg_phase_ != EGPhase::Release; }

    // Debug
    int32_t GetOutput() const { return out_; }

private:
    // Phase Generator state
    uint32_t pg_count_;      // Current phase counter (21-bit)
    uint32_t pg_diff_;       // Phase increment per sample
    int32_t detune_;         // Fine detune value (-3 to +3 cents)
    int32_t detune2_;        // Coarse detune value (semitones)

    // Envelope Generator state
    EGPhase eg_phase_;       // Current EG phase
    int32_t eg_level_;       // Current EG level (0-127, 0=quietest, 127=loudest)
    uint32_t eg_count_;      // EG counter for rate accumulation

    // OPM Register values
    uint8_t ar_;            // Attack Rate (0-31)
    uint8_t dr_;            // Decay Rate (0-31)
    uint8_t sr_;            // Sustain Rate (0-31)
    uint8_t rr_;            // Release Rate (0-31)
    uint8_t sl_;            // Sustain Level (0-127, in 3-bit steps)
    uint8_t tl_;            // Total Level (0-127)
    uint8_t kc_;            // Key Code (0-127)
    uint8_t kf_;            // Key Fraction (0-63)
    uint8_t ks_;            // Key Scale (0-3)
    uint8_t mul_;           // Frequency Multiplier (0-15)
    uint8_t dt1_;           // Detune 1 (0-7, yields -3 to +3 cents)
    uint8_t dt2_;           // Detune 2 (0-3, yields 0 to +3 semitones)
    uint8_t ssg_eg_;        // SSG-EG mode (0-15, unused in this implementation)

    bool am_on_;            // Amplitude Modulation enable
    bool keyon_;            // Key on state
    int32_t out_;           // Current operator output

    // Static lookup tables (initialized once)
    static bool tables_initialized_;
    static void InitializeTables();

    // Frequency multiplier table
    static uint32_t mul_table_[16];

    // Log-sine table (from Nuked-OPM)
    static uint32_t logsin_table_[256];

    // Exponential table (from Nuked-OPM)
    static uint32_t exp_table_[256];

    // EG step table (rate-to-increment mapping)
    static uint32_t eg_step_table_[64];

    // Helper functions
    void UpdateDetune();
    void UpdatePGDiff();
    void UpdateEG();
};

} // namespace opm

#endif // OPM_OPERATOR_H
