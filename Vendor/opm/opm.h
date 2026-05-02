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

#ifndef OPM_H
#define OPM_H

#include <cstdint>
#include <cstddef>

namespace opm {

// Sample type for audio output
using Sample = int16_t;
using ISample = int32_t;

// OPM has 8 channels, each with 4 operators
static constexpr int NUM_CHANNELS = 8;
static constexpr int NUM_OPERATORS = 4;

// Timer IDs
enum class TimerId {
    A,
    B
};

// LFO waveform types
enum class LfoWaveform {
    Saw,
    Square,
    Triangle,
    Noise
};

// Callback for interrupt notification
class OpmDevice;

// Channel state for UI (meters, etc.)
// Must match MP4MChannelState in MP4M-Bridging-Header.h exactly
struct ChannelState {
    uint8_t keyCode;
    uint8_t velocity;
    uint8_t keyOn;     // 0 = off, 1 = on (use uint8_t for C/Swift compatibility)
    uint8_t volume;
    int16_t bend;
    uint8_t pan;
    uint8_t keyOffset;
    uint8_t active;     // 0 = inactive, 1 = active
};

// Main OPM device class
class OpmDevice {
public:
    OpmDevice() = default;
    virtual ~OpmDevice() = default;

    // Initialize the OPM device
    // clock: OPM clock frequency in Hz (typically 3579545 for X68000)
    // sample_rate: audio sample rate in Hz (e.g., 44100)
    virtual bool Init(uint32_t clock, uint32_t sample_rate) = 0;

    // Reset the device to initial state
    virtual void Reset() = 0;

    // Write to a register
    virtual void WriteReg(uint8_t reg, uint8_t data) = 0;

    // Read status register
    virtual uint8_t ReadStatus() = 0;

    // Generate audio samples
    // buffer: output buffer, stereo interleaved (L, R, L, R...)
    // num_samples: number of sample pairs to generate
    virtual void Generate(Sample* buffer, size_t num_samples) = 0;

    // Alternative: generate and add to existing buffer (for mixing)
    virtual void Mix(Sample* buffer, size_t num_samples) = 0;

    // Timer control
    // Advance timers by given microseconds, returns true if interrupt occurred
    virtual bool AdvanceTimers(uint32_t microseconds) = 0;

    // Get microseconds until next timer event (for scheduling)
    virtual uint32_t GetNextEventTime() const = 0;

    // Set interrupt callback
    using InterruptCallback = void (*)(void* context, bool irq);
    virtual void SetInterruptCallback(InterruptCallback cb, void* context) = 0;

    // Volume control (in 0.5dB steps, 0 = full volume)
    virtual void SetVolume(int db) = 0;

    // Channel mask (bitmask, 1 = enabled)
    virtual void SetChannelMask(uint32_t mask) = 0;

    // Debug: get operator output
    virtual int32_t DebugGetOpOut(int ch, int op) const = 0;

    // Get channel states for UI
    virtual void GetChannelStates(ChannelState* states, int max_channels) = 0;
};

// Factory function to create OPM device
OpmDevice* CreateOpmDevice();
void DestroyOpmDevice(OpmDevice* device);

} // namespace opm

#endif // OPM_H
