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

#include "channel.h"

namespace opm {

// Nuked OPM OPM_LFOApplyPMS() の C++ 実装
// Reference: opm.c OPM_LFOApplyPMS()
static int32_t LFOApplyPMS(int32_t lfo, uint8_t pms) {
    if (pms == 0) {
        return 0;  // No PM when PMS=0
    }

    int32_t top = (lfo >> 4) & 7;   // Extract bits [6:4]

    if (pms != 7) {
        top >>= 1;
    }

    // Complex bit manipulation from Nuked OPM
    uint8_t t = ((top & 6) == 6) || ((top & 3) == 3 && pms >= 6);
    int32_t out = top + ((top >> 2) & 1) + t;
    out = out * 2 + ((lfo >> 4) & 1);

    if (pms == 7) {
        out >>= 1;
    }

    out &= 15;
    out = (lfo & 15) + (out * 16);  // out now 0-255

    // PMS-dependent shifting and masking
    switch (pms) {
    case 0:
        out = 0;
        break;
    case 1:
        out = (out >> 5) & 3;
        break;
    case 2:
        out = (out >> 4) & 7;
        break;
    case 3:
        out = (out >> 3) & 15;
        break;
    case 4:
        out = (out >> 2) & 31;
        break;
    case 5:
        out = (out >> 1) & 63;
        break;
    case 6:
        out = (out & 255) << 1;
        break;
    case 7:
        out = (out & 255) << 2;
        break;
    default:
        out = 0;
        break;
    }

    return out;
}

Channel::Channel() : algo_(Algorithm::A0), fb_(0), pan_(3),
                      pms_(0), ams_(0), fb_idx_(0) {
    fb_buf_[0] = 0;
    fb_buf_[1] = 0;
    for (int i = 0; i < 4; i++) {
        prev_op_out_[i] = 0;
    }
}

void Channel::SetAlgorithm(Algorithm algo) {
    algo_ = algo;
}

void Channel::SetFeedback(uint8_t fb) {
    fb_ = fb & 7;
}

void Channel::SetPMS(uint8_t pms) {
    pms_ = pms & 7;
}

void Channel::SetAMS(uint8_t ams) {
    ams_ = ams & 3;
}

void Channel::SetKCKF(uint8_t kc, uint8_t kf) {
    for (int i = 0; i < 4; i++) {
        ops_[i].SetKCKF(kc, kf);
    }
}

void Channel::KeyOn(uint8_t op_mask) {
    for (int i = 0; i < 4; i++) {
        if (op_mask & (1 << i)) {
            ops_[i].KeyOn();
        }
    }
}

void Channel::KeyOff(uint8_t op_mask) {
    for (int i = 0; i < 4; i++) {
        if (op_mask & (1 << i)) {
            ops_[i].KeyOff();
        }
    }
}

void Channel::SetOperatorParam(int op_idx, uint8_t dt1, uint8_t dt2,
                               uint8_t mul, uint8_t tl, uint8_t ar,
                               uint8_t dr, uint8_t sr,
                               uint8_t sl, uint8_t rr, bool am) {
    if (op_idx < 0 || op_idx >= 4) return;
    ops_[op_idx].SetDT(dt1);
    ops_[op_idx].SetDT2(dt2);
    ops_[op_idx].SetMUL(mul);
    ops_[op_idx].SetTL(tl);
    ops_[op_idx].SetAR(ar);
    ops_[op_idx].SetDR(dr);
    ops_[op_idx].SetSR(sr);
    ops_[op_idx].SetSL(sl);
    ops_[op_idx].SetRR(rr);
    ops_[op_idx].SetAM(am);
}

int32_t Channel::Calculate(int32_t am, int32_t pm) {
    // Apply PMS (PM sensitivity) using Nuked OPM logic
    // pm input: LFO raw value (from LFO)
    if (pms_ > 0) {
        pm = LFOApplyPMS(pm, pms_);  // Use corrected Nuked OPM implementation
    } else {
        pm = 0;
    }

    // Apply AMS (AM sensitivity)
    if (ams_ == 0) {
        am = 0;
    } else {
        // AMS 0-3: 0=no AM, 1=25%, 2=50%, 3=100%
        // Nuked OPM: eg_am = lfo_am_lock << (ams * 1/2/2)
        static const int32_t ams_shift[4] = {0, 2, 1, 0};  // >> shift
        am = (am >> ams_shift[ams_]) & 0x3FF;  // Clamp to 10-bit
    }
    
    int32_t result = 0;
    switch (algo_) {
        case Algorithm::A0: result = RouteA0(am, pm); break;
        case Algorithm::A1: result = RouteA1(am, pm); break;
        case Algorithm::A2: result = RouteA2(am, pm); break;
        case Algorithm::A3: result = RouteA3(am, pm); break;
        case Algorithm::A4: result = RouteA4(am, pm); break;
        case Algorithm::A5: result = RouteA5(am, pm); break;
        case Algorithm::A6: result = RouteA6(am, pm); break;
        case Algorithm::A7: result = RouteA7(am, pm); break;
        default: result = 0; break;
    }
    
    // Update previous outputs for next sample's delay
    for (int i = 0; i < 4; i++) {
        prev_op_out_[i] = ops_[i].GetOutput();
    }
    
    return result;
}

void Channel::Prepare() {
    for (int i = 0; i < 4; i++) {
        ops_[i].Prepare();
    }
    fb_idx_ = 1 - fb_idx_;
}

bool Channel::IsActive() const {
    for (int i = 0; i < 4; i++) {
        if (ops_[i].IsActive()) return true;
    }
    return false;
}

bool Channel::IsKeyOn() const {
    for (int i = 0; i < 4; i++) {
        if (ops_[i].IsKeyOn()) return true;
    }
    return false;
}

int32_t Channel::GetOutputLevel() const {
    int32_t total = 0;
    for (int i = 0; i < 4; i++) {
        total += ops_[i].GetOutput();
    }
    return total / 4;
}

// Algorithm implementations with 1-sample delay (cycle-based OPM matching)
int32_t Channel::RouteA0(int32_t am, int32_t pm) {
    // OP1 -> OP2 -> OP3 -> OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    // Use previous sample's output for delay
    int32_t out2 = ops_[1].Calculate(prev_op_out_[0], am, pm);
    int32_t out3 = ops_[2].Calculate(prev_op_out_[1], am, pm);
    int32_t out4 = ops_[3].Calculate(prev_op_out_[2], am, pm);
    return out4;
}

int32_t Channel::RouteA1(int32_t am, int32_t pm) {
    // OP1 -> OP2 -> OP3 + OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(prev_op_out_[0], am, pm);
    int32_t out3 = ops_[2].Calculate(prev_op_out_[1], am, pm);
    int32_t out4 = ops_[3].Calculate(0, am, pm);  // OP4 is carrier, no mod
    return out3 + out4;
}

int32_t Channel::RouteA2(int32_t am, int32_t pm) {
    // OP1 -> OP2 + OP3 + OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(prev_op_out_[0], am, pm);
    int32_t out3 = ops_[2].Calculate(prev_op_out_[0], am, pm);  // Both use OP1 delayed
    int32_t out4 = ops_[3].Calculate(prev_op_out_[0], am, pm);  // Both use OP1 delayed
    return out2 + out3 + out4;
}

int32_t Channel::RouteA3(int32_t am, int32_t pm) {
    // All operators in parallel (with 1-sample delay for consistency)
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);
    int32_t out3 = ops_[2].Calculate(0, am, pm);
    int32_t out4 = ops_[3].Calculate(0, am, pm);
    return prev_op_out_[0] + prev_op_out_[1] + prev_op_out_[2] + prev_op_out_[3];
}

int32_t Channel::RouteA4(int32_t am, int32_t pm) {
    // OP1 -> OP2 + OP3 -> OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ?0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(prev_op_out_[0], am, pm);
    int32_t out3 = ops_[2].Calculate(prev_op_out_[0], am, pm);
    int32_t out4 = ops_[3].Calculate(prev_op_out_[1] + prev_op_out_[2], am, pm);
    return out4;
}

int32_t Channel::RouteA5(int32_t am, int32_t pm) {
    // OP1 + OP2 -> OP3 -> OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ?0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);  // OP2 is parallel to OP1, no mod
    int32_t out3 = ops_[2].Calculate(prev_op_out_[0] + prev_op_out_[1], am, pm);
    int32_t out4 = ops_[3].Calculate(prev_op_out_[2], am, pm);
    return out4;
}

int32_t Channel::RouteA6(int32_t am, int32_t pm) {
    // OP1 + OP2 + OP3 -> OP4 -> Out (with 1-sample delay)
    int32_t fb = (fb_ == 0) ?0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);
    int32_t out3 = ops_[2].Calculate(0, am, pm);
    int32_t out4 = ops_[3].Calculate(prev_op_out_[0] + prev_op_out_[1] + prev_op_out_[2], am, pm);
    return out4;
}

int32_t Channel::RouteA7(int32_t am, int32_t pm) {
    // All parallel (same as A3, with 1-sample delay)
    int32_t fb = (fb_ == 0) ?0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    // Return sum of previous sample's operator outputs
    return prev_op_out_[0] + prev_op_out_[1] + prev_op_out_[2] + prev_op_out_[3];
}

} // namespace opm
