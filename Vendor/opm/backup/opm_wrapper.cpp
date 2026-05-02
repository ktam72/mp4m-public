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

#include "opm_wrapper.h"
#include <cstdio>

// Declare the export function from mxdrvg_core.h
extern "C" void OPMINTFUNC_Export(void);

// Interrupt function pointer (same as original FOOpmWrapper)
void (*OpmWrapper::OPMINT_FUNC)(void) = nullptr;

// Global wrapper instance for channel state access
static OpmWrapper* g_opmWrapper = nullptr;

OpmWrapper::OpmWrapper() : device_(nullptr), volume_db_(0) {
}

OpmWrapper::~OpmWrapper() {
    if (device_) {
        opm::DestroyOpmDevice(device_);
        device_ = nullptr;
    }
    if (g_opmWrapper == this) {
        g_opmWrapper = nullptr;
    }
}

// Set the global wrapper instance
void SetGlobalOpmWrapper(OpmWrapper* wrapper) {
    g_opmWrapper = wrapper;
}

// Get channel states from global wrapper
extern "C" void OPM_GetChannelStates(opm::ChannelState* states, int max_channels) {
    if (g_opmWrapper) {
        g_opmWrapper->GetChannelStates(states, max_channels);
    }
}

void OpmWrapper::InitWrapper(uint32_t clock, uint32_t rate, bool /*filter*/) {
    if (device_) {
        opm::DestroyOpmDevice(device_);
    }
    device_ = opm::CreateOpmDevice();
    if (device_) {
        device_->Init(clock, rate);
        device_->SetInterruptCallback(OPMINT_FUNC_Callback, this);
        device_->SetVolume(volume_db_);
    }
}

void OpmWrapper::SetVolumeWrapper(int db) {
    volume_db_ = db;
    if (device_) {
        device_->SetVolume(db);
    }
}

void OpmWrapper::SetRegWrapper(uint8_t addr, uint8_t data) {
    if (device_) {
        device_->WriteReg(addr, data);
    }
}

void OpmWrapper::MixWrapper(int16_t* buf, int nsamples) {
    if (device_) {
        device_->Mix(buf, nsamples);
    }
}

unsigned long OpmWrapper::GetNextEventWrapper() {
    if (device_) {
        return device_->GetNextEventTime();
    }
    return 0;
}

void OpmWrapper::CountWrapper(uint32_t us) {
    if (device_) {
        device_->AdvanceTimers(us);
    }
}

void OpmWrapper::OPMINT_FUNC_Callback(void* /*context*/, bool irq) {
    // This is called when OPM timer interrupt occurs
    // We need to call OPMINTFUNC() which updates G.PLAYTIME,
    // not just OPMINT_FUNC (L_OPMINT) which only does sequence processing.
    if (irq) {
        OPMINTFUNC_Export();
    }
}

void OpmWrapper::GetChannelStates(opm::ChannelState* states, int max_channels) {
    if (device_) {
        device_->GetChannelStates(states, max_channels);
    }
}
