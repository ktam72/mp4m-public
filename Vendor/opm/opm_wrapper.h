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

#ifndef OPM_WRAPPER_H
#define OPM_WRAPPER_H

#include "opm.h"

// OPM wrapper for MXDRVG compatibility
// This wrapper provides an interface similar to FOOpmWrapper but uses
// the new original OPM driver implementation
class OpmWrapper {
public:
    OpmWrapper();
    ~OpmWrapper();

    // Initialize the OPM device
    // clock: OPM clock frequency in Hz (typically 3579545 for X68000)
    // rate: audio sample rate in Hz (e.g., 44100)
    void InitWrapper(uint32_t clock, uint32_t rate, bool filter = false);

    // Set volume (in dB, 0 = full volume)
    void SetVolumeWrapper(int db);

    // Write to OPM register
    void SetRegWrapper(uint8_t addr, uint8_t data);

    // Mix audio samples
    // buf: output buffer, stereo interleaved (L, R, L, R...)
    // nsamples: number of sample pairs to generate
    void MixWrapper(int16_t* buf, int nsamples);

    // Get microseconds until next timer event
    unsigned long GetNextEventWrapper();

    // Advance timers by given microseconds
    // This should be called from MXDRVG's timer interrupt handler
    void CountWrapper(uint32_t us);

    // Interrupt callback for MXDRVG
    static void OPMINT_FUNC_Callback(void* context, bool irq);

    // Get channel states for UI
    void GetChannelStates(opm::ChannelState* states, int max_channels);

private:
    opm::OpmDevice* device_;
    int volume_db_;

public:
    // Static interrupt callback (public for access from mxdrvg_core.h)
    static void (*OPMINT_FUNC)(void);
};

#endif // OPM_WRAPPER_H
