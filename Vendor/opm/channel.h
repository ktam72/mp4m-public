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

#ifndef OPM_CHANNEL_H
#define OPM_CHANNEL_H

#include "operator.h"

namespace opm {

// Channel algorithm types (connection types)
enum class Algorithm {
    A0, // OP1 -> OP2 -> OP3 -> OP4 -> Out
    A1, // OP1 -> OP2 -> OP3 + OP4 -> Out
    A2, // OP1 -> OP2 + OP3 + OP4 -> Out
    A3, // OP1 + OP2 + OP3 + OP4 -> Out
    A4, // OP1 -> OP2 + OP3 -> OP4 -> Out
    A5, // OP1 + OP2 -> OP3 -> OP4 -> Out
    A6, // OP1 + OP2 + OP3 -> OP4 -> Out
    A7  // OP1 + OP2 + OP3 + OP4 -> Out (all parallel)
};

// Channel class - implements a 4-operator FM channel
class Channel {
public:
    Channel();

    // Set algorithm (connection type)
    void SetAlgorithm(Algorithm algo);

    // Set feedback level
    void SetFeedback(uint8_t fb);

    // Set key code and key fraction
    void SetKCKF(uint8_t kc, uint8_t kf);

    // Key control (on/off for specific operators)
    void KeyOn(uint8_t op_mask);
    void KeyOff(uint8_t op_mask);

    // Set parameters for each operator
    void SetOperatorParam(int op_idx, uint8_t dt1, uint8_t dt2, uint8_t mul,
                         uint8_t tl, uint8_t ar, uint8_t dr, uint8_t sr,
                         uint8_t sl, uint8_t rr, bool am);

    // Set PM/AM sensitivity
    void SetPMS(uint8_t pms);
    void SetAMS(uint8_t ams);

    // Calculate output for one sample
    int32_t Calculate(int32_t am, int32_t pm);

    // Prepare for next sample
    void Prepare();

    // Set pan (0=off, 1=L, 2=R, 3=L+R)
    void SetPan(uint8_t pan) { pan_ = pan & 3; }
    uint8_t GetPan() const { return pan_; }

    // Check if channel is active
    bool IsActive() const;

    // Check if any operator is key on
    bool IsKeyOn() const;

    // Get combined output level (for meter display)
    int32_t GetOutputLevel() const;

    // Get operator output (for debug)
    int32_t GetOpOut(int op_idx) const { return ops_[op_idx].GetOutput(); }

    // Direct operator access for register-based writes
    Operator* GetOperator(int op_idx) { return (op_idx >= 0 && op_idx < 4) ? &ops_[op_idx] : nullptr; }

private:
    Operator ops_[4];
    Algorithm algo_;
    uint8_t fb_;       // Feedback level
    uint8_t pan_;      // Pan: 0=off, 1=L, 2=R, 3=L+R
    uint8_t pms_;      // PM sensitivity (0-7)
    uint8_t ams_;      // AM sensitivity (0-3)

    // Feedback buffer
    int32_t fb_buf_[2];
    int fb_idx_;

    // Previous sample operator outputs (for 1-sample delay)
    int32_t prev_op_out_[4];

    // Algorithm routing
    int32_t RouteA0(int32_t am, int32_t pm);
    int32_t RouteA1(int32_t am, int32_t pm);
    int32_t RouteA2(int32_t am, int32_t pm);
    int32_t RouteA3(int32_t am, int32_t pm);
    int32_t RouteA4(int32_t am, int32_t pm);
    int32_t RouteA5(int32_t am, int32_t pm);
    int32_t RouteA6(int32_t am, int32_t pm);
    int32_t RouteA7(int32_t am, int32_t pm);
};

} // namespace opm

#endif // OPM_CHANNEL_H
