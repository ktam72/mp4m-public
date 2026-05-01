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

Channel::Channel() : algo_(Algorithm::A0), fb_(0), pan_(3),
                     fb_idx_(0) {
    fb_buf_[0] = 0;
    fb_buf_[1] = 0;
}

void Channel::SetAlgorithm(Algorithm algo) {
    algo_ = algo;
}

void Channel::SetFeedback(uint8_t fb) {
    fb_ = fb & 7;
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
    switch (algo_) {
        case Algorithm::A0: return RouteA0(am, pm);
        case Algorithm::A1: return RouteA1(am, pm);
        case Algorithm::A2: return RouteA2(am, pm);
        case Algorithm::A3: return RouteA3(am, pm);
        case Algorithm::A4: return RouteA4(am, pm);
        case Algorithm::A5: return RouteA5(am, pm);
        case Algorithm::A6: return RouteA6(am, pm);
        case Algorithm::A7: return RouteA7(am, pm);
        default: return 0;
    }
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

// Algorithm implementations
int32_t Channel::RouteA0(int32_t am, int32_t pm) {
    // OP1 -> OP2 -> OP3 -> OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(out1, am, pm);
    int32_t out3 = ops_[2].Calculate(out2, am, pm);
    int32_t out4 = ops_[3].Calculate(out3, am, pm);
    return out4;
}

int32_t Channel::RouteA1(int32_t am, int32_t pm) {
    // OP1 -> OP2 -> OP3 + OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(out1, am, pm);
    int32_t out3 = ops_[2].Calculate(out2, am, pm);
    int32_t out4 = ops_[3].Calculate(0, am, pm);
    return out3 + out4;
}

int32_t Channel::RouteA2(int32_t am, int32_t pm) {
    // OP1 -> OP2 + OP3 + OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(out1, am, pm);
    int32_t out3 = ops_[2].Calculate(out1, am, pm);
    int32_t out4 = ops_[3].Calculate(out1, am, pm);
    return out2 + out3 + out4;
}

int32_t Channel::RouteA3(int32_t am, int32_t pm) {
    // All operators in parallel
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);
    int32_t out3 = ops_[2].Calculate(0, am, pm);
    int32_t out4 = ops_[3].Calculate(0, am, pm);
    return out1 + out2 + out3 + out4;
}

int32_t Channel::RouteA4(int32_t am, int32_t pm) {
    // OP1 -> OP2 + OP3 -> OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(out1, am, pm);
    int32_t out3 = ops_[2].Calculate(out1, am, pm);
    int32_t out4 = ops_[3].Calculate(out2 + out3, am, pm);
    return out4;
}

int32_t Channel::RouteA5(int32_t am, int32_t pm) {
    // OP1 + OP2 -> OP3 -> OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);
    int32_t out3 = ops_[2].Calculate(out1 + out2, am, pm);
    int32_t out4 = ops_[3].Calculate(out3, am, pm);
    return out4;
}

int32_t Channel::RouteA6(int32_t am, int32_t pm) {
    // OP1 + OP2 + OP3 -> OP4 -> Out
    int32_t fb = (fb_ == 0) ? 0 : (fb_buf_[1 - fb_idx_] >> (8 - fb_));
    int32_t out1 = ops_[0].Calculate(fb, am, pm);
    fb_buf_[fb_idx_] = out1 << (fb_ + 8);
    
    int32_t out2 = ops_[1].Calculate(0, am, pm);
    int32_t out3 = ops_[2].Calculate(0, am, pm);
    int32_t out4 = ops_[3].Calculate(out1 + out2 + out3, am, pm);
    return out4;
}

int32_t Channel::RouteA7(int32_t am, int32_t pm) {
    // All parallel (same as A3)
    return RouteA3(am, pm);
}

} // namespace opm
