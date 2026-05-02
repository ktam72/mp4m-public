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

#ifndef OPM_TIMER_H
#define OPM_TIMER_H

#include <cstdint>

namespace opm {

// Timer class for YM2151 timers A and B
class Timer {
public:
    Timer();
    void Init(uint32_t clock_freq);

    // Set timer A (10-bit value from registers 0x10 and 0x11)
    void SetTimerA(uint16_t value);

    // Set timer B (8-bit value from register 0x12)
    void SetTimerB(uint8_t value);

    // Load timer (start counting)
    void LoadTimerA(bool load);
    void LoadTimerB(bool load);

    // Enable/disable timer interrupts
    void EnableTimerA(bool enable);
    void EnableTimerB(bool enable);

    // Reset timer interrupt flags
    void ResetTimerAFlag();
    void ResetTimerBFlag();

    // Check interrupt flags
    bool IsTimerAFlagSet() const { return timer_a_flag_; }
    bool IsTimerBFlagSet() const { return timer_b_flag_; }

    // Advance timers by given microseconds
    // Returns true if an interrupt occurred
    bool Advance(uint32_t microseconds);

    // Get microseconds until next timer event
    uint32_t GetNextEventTime() const;

    // Get Timer A overflow flag (for CSM mode)
    bool GetTimerAOverflow() const { return timer_a_flag_; }

    // Clear Timer A overflow flag (for CSM mode)
    void ClearTimerAOverflow() { timer_a_flag_ = false; }

    // Reset timers
    void Reset();

private:
    uint32_t clock_freq_;       // YM2151 clock frequency in Hz

    // Timer A: 10-bit prescaler, counts down
    uint16_t timer_a_value_;   // Load value (10-bit)
    uint32_t timer_a_count_;   // Current counter (µs単位、uint16_t/uint8_tではオーバーフローする)
    bool timer_a_load_;       // Load enable
    bool timer_a_enable_;     // Interrupt enable
    bool timer_a_flag_;       // Interrupt flag
    bool timer_a_active_;     // Currently counting

    // Timer B: 8-bit, counts down
    uint8_t timer_b_value_;    // Load value (8-bit)
    uint32_t timer_b_count_;   // Current counter (µs単位、uint8_tではオーバーフローする)
    bool timer_b_load_;       // Load enable
    bool timer_b_enable_;     // Interrupt enable
    bool timer_b_flag_;       // Interrupt flag
    bool timer_b_active_;     // Currently counting

    // Calculate timer A period in microseconds
    uint32_t GetTimerAPeriod() const;

    // Calculate timer B period in microseconds
    uint32_t GetTimerBPeriod() const;
};

} // namespace opm

#endif // OPM_TIMER_H
