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

#include "opm.h"
#include "channel.h"
#include "lfo.h"
#include "timer.h"
#include <cstring>
#include <cmath>

namespace opm {

// Static table for frequency calculation
static uint32_t freq_table[1024] = {0};
static bool freq_table_init = false;

static void InitFreqTable() {
    if (freq_table_init) return;
    for (int i = 0; i < 1024; i++) {
        // Convert block/note to frequency
        // KC: 3 bits block + 4 bits note
        // KF: 6 bits fraction
        int block = (i >> 7) & 7;
        int note = (i >> 3) & 15;
        int kf = i & 7;
        double freq = 440.0 * pow(2.0, (note - 69 + block * 12) / 12.0);
        freq_table[i] = static_cast<uint32_t>(freq * 256) + kf;
    }
    freq_table_init = true;
}

class OpmDeviceImpl : public OpmDevice {
public:
    OpmDeviceImpl();
    ~OpmDeviceImpl() override = default;

    bool Init(uint32_t clock, uint32_t sample_rate) override;
    void Reset() override;
    void WriteReg(uint8_t reg, uint8_t data) override;
    uint8_t ReadStatus() override;
    void Generate(Sample* buffer, size_t num_samples) override;
    void Mix(Sample* buffer, size_t num_samples) override;
    bool AdvanceTimers(uint32_t microseconds) override;
    uint32_t GetNextEventTime() const override;
    void SetVolume(int db) override;
    void SetChannelMask(uint32_t mask) override;
    void SetInterruptCallback(InterruptCallback cb, void* context) override;
    int32_t DebugGetOpOut(int ch, int op) const override;

private:
    uint32_t clock_;
    uint32_t sample_rate_;
    int volume_;  // in 0.5dB steps

    // Registers (256 bytes)
    uint8_t regs_[256];

    // Channels
    Channel channels_[8];

    // LFO
    LFO lfo_;

    // Timers
    Timer timers_;
    uint16_t timer_a_high_;   // High 2 bits of timer A (from reg 0x10)
    uint16_t timer_a_low_;    // Low 8 bits of timer A (from reg 0x11)

    // Noise - LFSR implementation (Nuked OPM)
    uint16_t noise_lfsr_;       // 16-bit Linear Feedback Shift Register
    uint8_t noise_bit_;         // feedback bit storage
    uint8_t noise_timer_;       // 5-bit timer (0-31) for noise update frequency
    uint8_t noise_update_;      // update flag (timer overflow)
    uint8_t noise_freq_;        // frequency setting from register 0x0F[3:0]
    uint8_t noise_timer_of_;    // timer overflow flag

    // Legacy noise mode field
    uint8_t noise_mode_;

    // Status register
    uint8_t status_;

    // Interrupt callback
    InterruptCallback intr_cb_;
    void* intr_context_;

    // Channel mask
    uint32_t channel_mask_;

    // KC/KF storage
    uint8_t kc_[8];
    uint8_t kf_[8];

    // CSM Mode (Composite Sinusoidal Modulation)
    uint8_t mode_csm_;          // CSM mode enable (register 0x14 bit 7)
    uint8_t kon_csm_;           // Channel mask for CSM KeyOn (4 bits)
    uint8_t kon_csm_lock_;      // Lock flag to prevent multiple KeyOn per overflow

    // Internal methods - register dispatch
    void WriteReg00(uint8_t reg, uint8_t data);   // Registers 0x00-0x1F
    void WriteReg20_RLFB(uint8_t reg, uint8_t data);  // 0x20-0x27: RL/FB/CONNECT
    void WriteReg28_KC(uint8_t reg, uint8_t data);  // 0x28-0x2F: KC
    void WriteReg30_KF(uint8_t reg, uint8_t data);  // 0x30-0x37: KF
    void WriteReg38_PMSAMS(uint8_t reg, uint8_t data); // 0x38-0x3F: PMS/AMS
    void WriteReg40_DT1MUL(uint8_t reg, uint8_t data); // 0x40-0x5F: DT1/MUL
    void WriteReg60_TL(uint8_t reg, uint8_t data); // 0x60-0x7F: TL
    void WriteReg80_KSAR(uint8_t reg, uint8_t data); // 0x80-0x9F: KS/AR
    void WriteRegA0_AMSD1R(uint8_t reg, uint8_t data); // 0xA0-0xBF: AMS-EN/D1R
    void WriteRegC0_DT2D2R(uint8_t reg, uint8_t data); // 0xC0-0xDF: DT2/D2R
    void WriteRegE0_D1LRR(uint8_t reg, uint8_t data); // 0xE0-0xFF: D1L/RR

    // Channel state
    void GetChannelStates(ChannelState* states, int max_channels) override;

    void UpdateKey(uint8_t ch, uint8_t keyon);
    void UpdatePan(uint8_t ch, uint8_t data);
    void UpdateAlgorithm(uint8_t ch, uint8_t data);
    void UpdateFeedback(uint8_t ch, uint8_t data);
    void UpdateKCKF(uint8_t ch, uint8_t kc, uint8_t kf);

    void GenerateNoise();
    uint16_t GetNoise() { return noise_lfsr_ & 1; }  // LFSR LSB output

    void CheckInterrupts();
};

OpmDevice* CreateOpmDevice() {
    return new OpmDeviceImpl();
}

void DestroyOpmDevice(OpmDevice* device) {
    delete device;
}

OpmDeviceImpl::OpmDeviceImpl()
    : clock_(0), sample_rate_(0), volume_(0),
      timer_a_high_(0), timer_a_low_(0),
      noise_lfsr_(0x0001), noise_bit_(0), noise_timer_(0),
      noise_update_(0), noise_freq_(0), noise_timer_of_(0),
      noise_mode_(0),
      status_(0),
      intr_cb_(nullptr), intr_context_(nullptr),
      channel_mask_(0xFFFFFFFF),
      mode_csm_(0), kon_csm_(0), kon_csm_lock_(0) {
    std::memset(regs_, 0, sizeof(regs_));
    std::memset(kc_, 0, sizeof(kc_));
    std::memset(kf_, 0, sizeof(kf_));
    if (!freq_table_init) {
        InitFreqTable();
    }
}

bool OpmDeviceImpl::Init(uint32_t clock, uint32_t sample_rate) {
    clock_ = clock;
    sample_rate_ = sample_rate;
    timers_.Init(clock_);  // Initialize timer with clock frequency
    Reset();
    return true;
}

void OpmDeviceImpl::Reset() {
    std::memset(regs_, 0, sizeof(regs_));
    for (int i = 0; i < 8; i++) {
        channels_[i].SetAlgorithm(Algorithm::A0);
        channels_[i].SetFeedback(0);
        channels_[i].SetPan(3);  // Both L+R
        for (int op = 0; op < 4; op++) {
            channels_[i].SetOperatorParam(op, 0, 0, 0, 127, 0, 0, 0, 0, 0, false);
        }
    }
    lfo_.Reset();
    timers_.Reset();

    // Noise LFSR reset
    noise_lfsr_ = 0x0001;  // Non-zero initial value (prevent all-zero)
    noise_bit_ = 0;
    noise_timer_ = 0;
    noise_update_ = 0;
    noise_freq_ = 0;
    noise_timer_of_ = 0;
    noise_mode_ = 0;

    // CSM Mode reset
    mode_csm_ = 0;
    kon_csm_ = 0;
    kon_csm_lock_ = 0;

    status_ = 0;
}

void OpmDeviceImpl::WriteReg(uint8_t reg, uint8_t data) {
    regs_[reg] = data;

    if (reg < 0x20) {
        WriteReg00(reg, data);
    } else if (reg < 0x28) {
        // 0x20-0x27: RL/FB/CONNECT (channel)
        WriteReg20_RLFB(reg, data);
    } else if (reg < 0x30) {
        // 0x28-0x2F: KC (Key Code)
        WriteReg28_KC(reg, data);
    } else if (reg < 0x38) {
        // 0x30-0x37: KF (Key Fraction)
        WriteReg30_KF(reg, data);
    } else if (reg < 0x40) {
        // 0x38-0x3F: PMS/AMS
        WriteReg38_PMSAMS(reg, data);
    } else if (reg < 0x60) {
        // 0x40-0x5F: DT1/MUL (operator)
        WriteReg40_DT1MUL(reg, data);
    } else if (reg < 0x80) {
        // 0x60-0x7F: TL
        WriteReg60_TL(reg, data);
    } else if (reg < 0xA0) {
        // 0x80-0x9F: KS/AR
        WriteReg80_KSAR(reg, data);
    } else if (reg < 0xC0) {
        // 0xA0-0xBF: AMS-EN/D1R
        WriteRegA0_AMSD1R(reg, data);
    } else if (reg < 0xE0) {
        // 0xC0-0xDF: DT2/D2R
        WriteRegC0_DT2D2R(reg, data);
    } else {
        // 0xE0-0xFF: D1L/RR
        WriteRegE0_D1LRR(reg, data);
    }
}

void OpmDeviceImpl::WriteReg00(uint8_t reg, uint8_t data) {
    switch (reg & 0xE0) {
        case 0x00:
            switch (reg) {
                case 0x01:  // Test register
                    break;
                case 0x08:  // Key on/off
                    UpdateKey(data & 7, (data >> 3) & 1);
                    break;
                case 0x0C:  // CSM KeyOn channel mask
                    // bits [3:0]: channel mask for CSM mode (which channels get KeyOn on Timer A overflow)
                    kon_csm_ = data & 0x0F;
                    break;
                case 0x0F:  // Noise frequency/mode
                    // bits [3:0]: noise frequency (for LFSR period control)
                    noise_freq_ = data & 0x0F;
                    // bits [7:4]: noise mode settings (legacy, kept for compatibility)
                    noise_mode_ = (data >> 4) & 0x0F;
                    break;
                case 0x10:  // Timer A high (bits 0-1 are high 2 bits of timer A)
                    timer_a_high_ = data & 0x03;  // YM2151: bits 0-1 = A8-A9
                    timers_.SetTimerA((timer_a_high_ << 8) | timer_a_low_);
                    break;
                case 0x11:  // Timer A low (8-bit)
                    timer_a_low_ = data;
                    timers_.SetTimerA((timer_a_high_ << 8) | timer_a_low_);
                    break;
                case 0x12:  // Timer B
                    timers_.SetTimerB(data);
                    break;
                case 0x14:  // Control
                    // Bit 0: Load Timer A
                    // Bit 1: Load Timer B
                    // Bit 2: Enable Timer A interrupt
                    // Bit 3: Enable Timer B interrupt
                    // Bit 4: Reset Timer A flag
                    // Bit 5: Reset Timer B flag
                    // Bit 7: CSM mode enable
                    if (data & 0x01) {
                        timers_.LoadTimerA(true);
                    }
                    if (data & 0x02) {
                        timers_.LoadTimerB(true);
                    }
                    // デバッグ: タイマーA/Bを常に有効化
                    timers_.EnableTimerA(true);
                    timers_.EnableTimerB(true);
                    if (data & 0x10) timers_.ResetTimerAFlag();
                    if (data & 0x20) timers_.ResetTimerBFlag();
                    // CSM mode control (bit 7)
                    mode_csm_ = (data >> 7) & 1;
                    if (!mode_csm_) {
                        kon_csm_lock_ = 0;  // Clear lock when CSM is disabled
                    }
                    CheckInterrupts();
                    break;
                case 0x18:  // LFO frequency
                    lfo_.SetFrequency(data & 0x1F);
                    break;
                case 0x19: { // LFO PMD/AMD
                    // bit 7: 1=PMD, 0=AMD
                    uint8_t depth = data & 0x7F;
                    if (data & 0x80) {
                        lfo_.SetPMD(depth);  // Pitch Modulation Depth
                    } else {
                        lfo_.SetAMD(depth);  // Amplitude Modulation Depth
                    }
                    break;
                }
                case 0x1B:  // LFO waveform
                    {
                        uint8_t wav = data & 3;
                        LfoWave wave = LfoWave::Saw;
                        if (wav == 0) wave = LfoWave::Saw;
                        else if (wav == 1) wave = LfoWave::Square;
                        else if (wav == 2) wave = LfoWave::Triangle;
                        else wave = LfoWave::Noise;
                        lfo_.SetWaveform(wave);
                    }
                    break;
                default:
                    break;
            }
            break;
        default:
            break;
    }
}

void OpmDeviceImpl::WriteReg20_RLFB(uint8_t reg, uint8_t data) {
    // 0x20-0x27: RL/FB/CONNECT (channel)
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    uint8_t rl = (data >> 6) & 3;  // Pan (RL)
    uint8_t fb = (data >> 3) & 7;  // Feedback
    uint8_t connect = data & 7;      // Algorithm (CONNECT)
    channels_[ch].SetPan(rl);
    channels_[ch].SetFeedback(fb);
    channels_[ch].SetAlgorithm(static_cast<Algorithm>(connect));
}

void OpmDeviceImpl::WriteReg28_KC(uint8_t reg, uint8_t data) {
    // 0x28-0x2F: KC (Key Code)
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    kc_[ch] = data & 0x7F;
    channels_[ch].SetKCKF(kc_[ch], kf_[ch]);
}

void OpmDeviceImpl::WriteReg30_KF(uint8_t reg, uint8_t data) {
    // 0x30-0x37: KF (Key Fraction)
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    kf_[ch] = (data >> 2) & 0x3F;
    channels_[ch].SetKCKF(kc_[ch], kf_[ch]);
}

void OpmDeviceImpl::WriteReg38_PMSAMS(uint8_t reg, uint8_t data) {
    // 0x38-0x3F: PMS (bits 4-6) and AMS (bits 0-1)
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    
    uint8_t pms = (data >> 4) & 7;  // Pitch Modulation Sensitivity (3 bits)
    uint8_t ams = data & 3;        // Amplitude Modulation Sensitivity (2 bits)
    
    channels_[ch].SetPMS(pms);
    channels_[ch].SetAMS(ams);
}

void OpmDeviceImpl::WriteReg40_DT1MUL(uint8_t reg, uint8_t data) {
    // 0x40-0x5F: DT1/MUL (operator)
    uint8_t offset = reg - 0x40;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (op_ptr) {
        op_ptr->SetDT(data >> 4);
        op_ptr->SetMUL(data & 0x0F);
    }
}

void OpmDeviceImpl::WriteReg60_TL(uint8_t reg, uint8_t data) {
    // 0x60-0x7F: TL
    uint8_t offset = reg - 0x60;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (op_ptr) {
        op_ptr->SetTL(data & 0x7F);
    }
}

void OpmDeviceImpl::WriteReg80_KSAR(uint8_t reg, uint8_t data) {
    // 0x80-0x9F: KS/AR (operator)
    // Decode: reg = 0x80 + op*8 + ch
    uint8_t offset = reg - 0x80;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    uint8_t ks = (data >> 6) & 3;
    uint8_t ar = data & 0x1F;
    op_ptr->SetKS(ks);
    op_ptr->SetAR(ar);
}

void OpmDeviceImpl::WriteRegA0_AMSD1R(uint8_t reg, uint8_t data) {
    // 0xA0-0xBF: AMS-EN/D1R (operator)
    // Decode: reg = 0xA0 + op*8 + ch
    uint8_t offset = reg - 0xA0;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    bool ams_en = (data >> 7) & 1;
    uint8_t d1r = data & 0x1F;
    op_ptr->SetAM(ams_en);
    op_ptr->SetDR(d1r);
}

void OpmDeviceImpl::WriteRegC0_DT2D2R(uint8_t reg, uint8_t data) {
    // 0xC0-0xDF: DT2/D2R (operator)
    // Decode: reg = 0xC0 + op*8 + ch
    uint8_t offset = reg - 0xC0;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    uint8_t dt2 = (data >> 6) & 3;
    uint8_t d2r = data & 0x1F;
    op_ptr->SetDT2(dt2);
    op_ptr->SetSR(d2r);
}

void OpmDeviceImpl::WriteRegE0_D1LRR(uint8_t reg, uint8_t data) {
    // 0xE0-0xFF: D1L/RR (operator)
    // Decode: reg = 0xE0 + op*8 + ch
    uint8_t offset = reg - 0xE0;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    if (ch >= 8 || op >= 4) return;
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    uint8_t d1l = (data >> 4) & 0x0F;
    uint8_t rr = data & 0x0F;
    op_ptr->SetSL(d1l);
    op_ptr->SetRR(rr);
}

void OpmDeviceImpl::UpdateKey(uint8_t ch, uint8_t keyon) {
    if (ch >= 8) return;
    if (keyon) {
        channels_[ch].KeyOn(0x0F);  // Key on all operators
    } else {
        channels_[ch].KeyOff(0x0F);  // Key off all operators
    }
}

void OpmDeviceImpl::UpdateKCKF(uint8_t ch, uint8_t kc, uint8_t kf) {
    if (ch >= 8) return;
    kc_[ch] = kc;
    kf_[ch] = kf;
    channels_[ch].SetKCKF(kc_[ch], kf_[ch]);
}

void OpmDeviceImpl::GetChannelStates(ChannelState* states, int max_channels) {
    // Return channel states for UI (meters, etc.)
    // max_channels should be 16 (8 FM + 8 PCM)
    for (int ch = 0; ch < 8 && ch < max_channels; ch++) {
        states[ch].active = channels_[ch].IsActive() ? 1 : 0;
        states[ch].keyOn = channels_[ch].IsKeyOn() ? 1 : 0;
        states[ch].keyCode = kc_[ch];
        states[ch].volume = static_cast<uint8_t>(channels_[ch].GetOutputLevel());
        states[ch].bend = 0;  // TODO: calculate from KF if needed
        states[ch].pan = channels_[ch].GetPan();
        states[ch].keyOffset = 0;  // TODO: calculate if needed
        // Calculate velocity from volume (TL inverse)
        states[ch].velocity = static_cast<uint8_t>(127 - states[ch].volume);
    }
    // PCM channels (8-15) are not handled by OPM - set to 0
    for (int ch = 8; ch < max_channels; ch++) {
        states[ch].active = 0;
        states[ch].keyOn = 0;
        states[ch].keyCode = 0;
        states[ch].volume = 0;
        states[ch].bend = 0;
        states[ch].pan = 3;
        states[ch].keyOffset = 0;
        states[ch].velocity = 0;
    }
}

uint8_t OpmDeviceImpl::ReadStatus() {
    return status_ & 0x03;  // Only bits 0 and 1 are valid
}

void OpmDeviceImpl::Generate(Sample* buffer, size_t num_samples) {
    std::memset(buffer, 0, num_samples * 2 * sizeof(Sample));
    Mix(buffer, num_samples);
}

void OpmDeviceImpl::Mix(Sample* buffer, size_t num_samples) {
    for (size_t i = 0; i < num_samples; i++) {
        // Every sample update EG state
        for (int ch = 0; ch < 8; ch++) {
            if (channel_mask_ & (1 << ch)) {
                channels_[ch].Prepare();
            }
        }
        
        // Advance LFO
        lfo_.Advance(1);
        int32_t am = lfo_.GetAM() << 16;
        int32_t pm = lfo_.GetPM();
        
        // Generate for each channel
        int32_t left = 0, right = 0;
        
        for (int ch = 0; ch < 8; ch++) {
            if (!(channel_mask_ & (1 << ch))) continue;
            if (!channels_[ch].IsActive()) continue;
            
            int32_t out = channels_[ch].Calculate(am, pm);
            
            uint8_t pan = channels_[ch].GetPan();
            if (pan & 1) left += out;   // L
            if (pan & 2) right += out;  // R
        }

        // Output from Calculate() is ~14-bit signed
        // After mixing 8 channels, we get ~17-bit values
        // Scale down to 16-bit range to prevent clipping
        left >>= 1;   // Divide by 2 to stay in 16-bit range
        right >>= 1;

        // Apply volume (volume_ is in 0.5dB steps, 0 = full volume)
        if (volume_ > 0) {
            left >>= (volume_ / 2);
            right >>= (volume_ / 2);
        }

        // Clip and store
        if (left < -32768) left = -32768;
        if (left > 32767) left = 32767;
        if (right < -32768) right = -32768;
        if (right > 32767) right = 32767;
        buffer[i * 2 + 0] = static_cast<Sample>(left);
        buffer[i * 2 + 1] = static_cast<Sample>(right);
    }
}

bool OpmDeviceImpl::AdvanceTimers(uint32_t microseconds) {
    bool interrupted = timers_.Advance(microseconds);

    // CSM Mode: trigger KeyOn when Timer A overflows (if CSM is enabled)
    if (mode_csm_ && timers_.GetTimerAOverflow()) {
        // Check lock to prevent multiple KeyOn per single overflow
        if (!kon_csm_lock_) {
            // Trigger KeyOn for channels specified in kon_csm_ (lower 4 bits of reg 0x0C)
            for (int ch = 0; ch < 8; ch++) {
                if (kon_csm_ & (1 << ch)) {
                    channels_[ch].KeyOn(0x0F);  // KeyOn all 4 operators
                }
            }
            kon_csm_lock_ = 1;  // Set lock to prevent multiple KeyOn
        }
        timers_.ClearTimerAOverflow();  // Clear the overflow flag
    } else if (!timers_.GetTimerAOverflow()) {
        // Clear lock when Timer A overflow is no longer active
        kon_csm_lock_ = 0;
    }

    if (interrupted) {
        CheckInterrupts();
    }
    return interrupted;
}

uint32_t OpmDeviceImpl::GetNextEventTime() const {
    return timers_.GetNextEventTime();
}

void OpmDeviceImpl::SetVolume(int db) {
    volume_ = db;
}

void OpmDeviceImpl::SetChannelMask(uint32_t mask) {
    channel_mask_ = mask;
}

void OpmDeviceImpl::SetInterruptCallback(InterruptCallback cb, void* context) {
    intr_cb_ = cb;
    intr_context_ = context;
}

int32_t OpmDeviceImpl::DebugGetOpOut(int ch, int op) const {
    if (ch < 0 || ch >= 8 || op < 0 || op >= 4) return 0;
    return channels_[ch].GetOpOut(op);
}

void OpmDeviceImpl::GenerateNoise() {
    // Nuked OPM LFSR-based noise generation
    // Timer update: increment noise_timer each sample
    uint8_t timer = noise_timer_;
    timer++;
    timer &= 31;  // 5-bit counter (0-31)

    // Overflow detection (Nuked OPM logic)
    noise_timer_of_ = (timer == (noise_freq_ ^ 31)) ? 1 : 0;

    // Update flag follows timer overflow
    noise_update_ = noise_timer_of_;

    // LFSR update when noise_update is set
    uint8_t bit = 0;
    if (noise_update_) {
        // LFSR Feedback: bit[2] XOR bit[0], with reset-to-1 if all zeros
        uint8_t rst = ((noise_lfsr_ & 0xFFFF) == 0 && noise_bit_ == 0) ? 1 : 0;
        uint8_t xr = ((noise_lfsr_ >> 2) & 1) ^ noise_bit_;
        bit = rst | xr;

        // Store current bit[0] for next iteration
        noise_bit_ = noise_lfsr_ & 1;
    } else {
        // No update: output current bit[0]
        bit = noise_lfsr_ & 1;
    }

    // Shift LFSR right and insert feedback at bit 15
    noise_lfsr_ >>= 1;
    noise_lfsr_ |= (bit << 15);
    noise_lfsr_ &= 0xFFFF;  // 16-bit mask

    // Store updated timer
    noise_timer_ = timer;
}

void OpmDeviceImpl::CheckInterrupts() {
    bool irq = timers_.IsTimerAFlagSet() || timers_.IsTimerBFlagSet();
    status_ = (timers_.IsTimerAFlagSet() ? 1 : 0) |
              (timers_.IsTimerBFlagSet() ? 2 : 0);
    
    if (intr_cb_ && irq) {
        intr_cb_(intr_context_, true);
    }
}

} // namespace opm
