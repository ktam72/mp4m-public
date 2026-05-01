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
#include <algorithm>

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

    // Noise
    uint8_t noise_mode_;
    uint16_t noise_count_;
    uint32_t noise_delta_;

    // Status register
    uint8_t status_;

    // Interrupt callback
    InterruptCallback intr_cb_;
    void* intr_context_;

    // Channel mask
    uint32_t channel_mask_;

    // Internal methods
    void WriteReg00(uint8_t reg, uint8_t data);  // Registers 0x00-0x1F
    void WriteReg20(uint8_t reg, uint8_t data);  // Registers 0x20-0x3F
    void WriteReg40(uint8_t reg, uint8_t data);  // Registers 0x40-0x5F
    void WriteReg60(uint8_t reg, uint8_t data);  // Registers 0x60-0x7F
    void WriteReg80(uint8_t reg, uint8_t data);  // Registers 0x80-0x9F
    void WriteRegA0(uint8_t reg, uint8_t data);  // Registers 0xA0-0xBF
    void WriteRegC0(uint8_t reg, uint8_t data);  // Registers 0xC0-0xDF
    void WriteRegE0(uint8_t reg, uint8_t data);  // Registers 0xE0-0xFF

    void UpdateKey(uint8_t ch, uint8_t keyon);
    void UpdatePan(uint8_t ch, uint8_t data);
    void UpdateAlgorithm(uint8_t ch, uint8_t data);
    void UpdateFeedback(uint8_t ch, uint8_t data);
    void UpdateKCKF(uint8_t ch, uint8_t kc, uint8_t kf);

    void GenerateNoise();
    uint16_t GetNoise() { return noise_count_ & 1; }

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
      noise_mode_(0), noise_count_(0), noise_delta_(0),
      status_(0),
      intr_cb_(nullptr), intr_context_(nullptr),
      channel_mask_(0xFFFFFFFF),
      timer_a_high_(0), timer_a_low_(0) {
    std::memset(regs_, 0, sizeof(regs_));
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
    noise_mode_ = 0;
    noise_count_ = 0;
    noise_delta_ = 0;
    status_ = 0;
}

void OpmDeviceImpl::WriteReg(uint8_t reg, uint8_t data) {
    static int write_count = 0;
    // デバッグ: レジスタ書き込みをログ（初期化完了後の方が重要）
    
    regs_[reg] = data;

    if (reg < 0x20) {
        WriteReg00(reg, data);
    } else if (reg < 0x40) {
        WriteReg20(reg, data);
    } else if (reg < 0x60) {
        WriteReg40(reg, data);
    } else if (reg < 0x80) {
        WriteReg60(reg, data);
    } else if (reg < 0xA0) {
        WriteReg80(reg, data);
    } else if (reg < 0xC0) {
        WriteRegA0(reg, data);
    } else if (reg < 0xE0) {
        fprintf(stderr, "[OPM DISPATCH] Calling WriteRegC0 for reg=0x%02X\n", reg);
        WriteRegC0(reg, data);
    } else {
        fprintf(stderr, "[OPM DISPATCH] Calling WriteRegE0 for reg=0x%02X\n", reg);
        WriteRegE0(reg, data);
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
                case 0x0F:  // Noise mode
                    noise_mode_ = data;
                    break;
                case 0x10:  // Timer A high (bits 2-3 are high 2 bits of timer A)
                    timer_a_high_ = (data >> 2) & 0x03;
                    timers_.SetTimerA((timer_a_high_ << 8) | timer_a_low_);
                    fprintf(stderr, "[OPM] Set Timer A high: NA=%u (from 0x%02X), combined=%u\n", 
                        (timer_a_high_ << 8) | timer_a_low_, data, (timer_a_high_ << 8) | timer_a_low_);
                    break;
                case 0x11:  // Timer A low (8-bit)
                    timer_a_low_ = data;
                    timers_.SetTimerA((timer_a_high_ << 8) | timer_a_low_);
                    fprintf(stderr, "[OPM] Set Timer A low: NA=%u (from 0x%02X), combined=%u\n", 
                        (timer_a_high_ << 8) | timer_a_low_, data, (timer_a_high_ << 8) | timer_a_low_);
                    break;
                case 0x12:  // Timer B
                    timers_.SetTimerB(data);
                    fprintf(stderr, "[OPM] Set Timer B: NB=%u\n", data);
                    break;
                case 0x14:  // Control
                    // Bit 0: Load Timer A
                    // Bit 1: Load Timer B
                    // Bit 2: Enable Timer A interrupt
                    // Bit 3: Enable Timer B interrupt
                    // Bit 4: Reset Timer A flag
                    // Bit 5: Reset Timer B flag
                    if (data & 0x01) {
                        timers_.LoadTimerA(true);
                        fprintf(stderr, "[OPM] Load Timer A\n");
                    }
                    if (data & 0x02) {
                        timers_.LoadTimerB(true);
                        fprintf(stderr, "[OPM] Load Timer B\n");
                    }
                    timers_.EnableTimerA((data >> 2) & 1);
                    timers_.EnableTimerB((data >> 3) & 1);
                    if (data & 0x10) timers_.ResetTimerAFlag();
                    if (data & 0x20) timers_.ResetTimerBFlag();
                    CheckInterrupts();
                    break;
                case 0x18:  // LFO frequency
                    lfo_.SetFrequency(data & 0x1F);
                    break;
                case 0x19:  // LFO PMD/AMD
                    // bit 7: 1=PMD, 0=AMD
                    break;
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

void OpmDeviceImpl::WriteReg20(uint8_t reg, uint8_t data) {
    // Channel mode: RL, FB, CONECT
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    
    uint8_t rl = (data >> 6) & 3;  // Pan
    uint8_t fb = (data >> 3) & 7;  // Feedback
    uint8_t conect = data & 7;        // Algorithm
    
    channels_[ch].SetPan(rl);
    channels_[ch].SetFeedback(fb);
    channels_[ch].SetAlgorithm(static_cast<Algorithm>(conect));
}

void OpmDeviceImpl::WriteReg40(uint8_t reg, uint8_t data) {
    // Key code (KC)
    // For now, this is not used (KC/KF combined in WriteReg60)
}

void OpmDeviceImpl::WriteReg60(uint8_t reg, uint8_t data) {
    // Key fraction (KF)
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    uint8_t kf = (data >> 2) & 0x3F;
    uint8_t kc = data & 0x7F;
    UpdateKCKF(ch, kc, kf);
}

void OpmDeviceImpl::WriteReg80(uint8_t reg, uint8_t data) {
    // Operator parameters: DT1, MUL
    uint8_t ch = reg & 7;
    if (ch >= 8) return;
    uint8_t op = (reg >> 3) & 3;
    uint8_t dt1 = (data >> 4) & 7;
    uint8_t mul = data & 15;
    
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (op_ptr) {
        op_ptr->SetDT(dt1);
        op_ptr->SetMUL(mul);
    }
}

void OpmDeviceImpl::WriteRegA0(uint8_t reg, uint8_t data) {
    // YM2151 registers 0xA0-0xBF contain operator-specific parameters
    // Layout (by datasheet):
    // 0xA0-0xA7: Operator 0 TL (channels 0-7)
    // 0xA8-0xAF: Operator 1 TL (channels 0-7)
    // 0xB0-0xB7: Operator 2 TL (channels 0-7)
    // 0xB8-0xBF: Operator 3 TL (channels 0-7)
    // [Followed by similar ranges for other parameters at 0xC0-0xFF]
    
    // Decode: reg = 0xA0 + op*8 + ch
    uint8_t offset = reg - 0xA0;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    
    if (ch >= 8 || op >= 4) return;
    
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    
    // 0xA0-0xBF are all TL (Total Level) for operators 0-3
    uint8_t tl = data & 0x7F;
    op_ptr->SetTL(tl);
}

void OpmDeviceImpl::WriteRegC0(uint8_t reg, uint8_t data) {
    // YM2151 registers 0xC0-0xDF:
    // 0xC0-0xC7: Operator 0 KS/AR (channels 0-7)
    // 0xC8-0xCF: Operator 1 KS/AR
    // 0xD0-0xD7: Operator 2 KS/AR
    // 0xD8-0xDF: Operator 3 KS/AR
    
    // Decode: reg = 0xC0 + op*8 + ch
    uint8_t offset = reg - 0xC0;
    uint8_t op = offset / 8;
    uint8_t ch = offset % 8;
    
    if (ch >= 8 || op >= 4) return;
    
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) return;
    
    // KS/AR register
    // KS: bits 7-6 (Key Scale)
    // AR: bits 4-0 (Attack Rate)
    uint8_t ks = (data >> 6) & 3;
    uint8_t ar = data & 0x1F;
    
    op_ptr->SetAR(ar);
    // TODO: SetKS(ks)
    
    fprintf(stderr, "[WriteRegC0] reg=0x%02X: op=%d, ch=%d, AR=0x%02X, KS=%d\n", reg, op, ch, ar, ks);
}

void OpmDeviceImpl::WriteRegE0(uint8_t reg, uint8_t data) {
    // YM2151 registers 0xE0-0xFF:
    // 0xE0-0xE7: Operator 0 DR/SR (channels 0-7)
    // 0xE8-0xEF: Operator 1 DR/SR
    // 0xF0-0xF7: Operator 2 RR/SL
    // 0xF8-0xFF: Operator 3 RR/SL
    
    fprintf(stderr, "[WriteRegE0] ENTRY: reg=0x%02X, data=0x%02X (raw data)\n", reg, data);
    
    uint8_t offset = reg - 0xE0;
    uint8_t section = offset / 8;  // 0: OP0 DR/SR, 1: OP1 DR/SR, 2: OP2 RR/SL, 3: OP3 RR/SL
    uint8_t ch = offset % 8;
    
    if (ch >= 8) {
        fprintf(stderr, "[WriteRegE0] SKIP: ch=%d >= 8\n", ch);
        return;
    }
    
    // Map register sections to operators
    // 0xE0-0xE7: OP0, 0xE8-0xEF: OP1
    // 0xF0-0xF7: OP2, 0xF8-0xFF: OP3
    uint8_t op = (section < 2) ? section : (section - 2 + 2);
    
    Operator* op_ptr = channels_[ch].GetOperator(op);
    if (!op_ptr) {
        fprintf(stderr, "[WriteRegE0] FAIL: GetOperator returned null for ch=%d, op=%d\n", ch, op);
        return;
    }
    
    if (reg < 0xF0) {
        // DR/SR register (0xE0-0xEF)
        uint8_t dr = (data >> 4) & 0x0F;
        uint8_t sr = data & 0x0F;
        
        op_ptr->SetDR(dr);
        op_ptr->SetSR(sr);
        
        fprintf(stderr, "[WriteRegE0] DR/SR: reg=0x%02X, op=%d, ch=%d, DR=0x%02X, SR=0x%02X\n", reg, op, ch, dr, sr);
    } else {
        // RR/SL register (0xF0-0xFF)
        uint8_t rr = (data >> 4) & 0x0F;
        uint8_t sl = data & 0x0F;
        
        op_ptr->SetRR(rr);
        op_ptr->SetSL(sl);
        
        fprintf(stderr, "[WriteRegE0] RR/SL: reg=0x%02X, op=%d, ch=%d, RR=0x%02X, SL=0x%02X\n", reg, op, ch, rr, sl);
    }
}

void OpmDeviceImpl::UpdateKey(uint8_t ch, uint8_t keyon) {
    if (ch >= 8) return;
    if (keyon) {
        channels_[ch].KeyOn(0x0F);  // Key on all operators
    } else {
        channels_[ch].KeyOff(0x0F);  // Key off all operators
    }
}

void OpmDeviceImpl::UpdatePan(uint8_t ch, uint8_t data) {
    if (ch >= 8) return;
    channels_[ch].SetPan(data & 3);
}

void OpmDeviceImpl::UpdateAlgorithm(uint8_t ch, uint8_t data) {
    if (ch >= 8) return;
    channels_[ch].SetAlgorithm(static_cast<Algorithm>(data & 7));
}

void OpmDeviceImpl::UpdateFeedback(uint8_t ch, uint8_t data) {
    if (ch >= 8) return;
    channels_[ch].SetFeedback(data & 7);
}

void OpmDeviceImpl::UpdateKCKF(uint8_t ch, uint8_t kc, uint8_t kf) {
    if (ch >= 8) return;
    channels_[ch].SetKCKF(kc, kf);
}

uint8_t OpmDeviceImpl::ReadStatus() {
    return status_ & 0x03;  // Only bits 0 and 1 are valid
}

void OpmDeviceImpl::Generate(Sample* buffer, size_t num_samples) {
    std::memset(buffer, 0, num_samples * 2 * sizeof(Sample));
    Mix(buffer, num_samples);
}

void OpmDeviceImpl::Mix(Sample* buffer, size_t num_samples) {
    static int mix_call_count = 0;
    static int non_zero_count = 0;
    static int active_ch_count = 0;
    static int32_t max_left = 0, max_right = 0;
    static int sample_count = 0;
    static const int FRAME_SAMPLES = 735;  // 44100 / 60 fps
    
    for (size_t i = 0; i < num_samples; i++) {
        // Every sample update EG状態を更新
        for (int ch = 0; ch < 8; ch++) {
            if (channel_mask_ & (1 << ch)) {
                channels_[ch].Prepare();
            }
        }
        sample_count++;
        
        // Advance LFO
        lfo_.Advance(1);
        int32_t am = lfo_.GetAM() << 16;
        int32_t pm = lfo_.GetPM();

        // Generate noise
        GenerateNoise();
        int32_t noise = GetNoise() ? (1 << 24) : -(1 << 24);

        // Generate for each channel
        int32_t left = 0, right = 0;
        int ch_active = 0;
        
        for (int ch = 0; ch < 8; ch++) {
            if (!(channel_mask_ & (1 << ch))) continue;
            if (!channels_[ch].IsActive()) continue;
            ch_active++;
            
            int32_t out = channels_[ch].Calculate(am, pm);
            
            uint8_t pan = channels_[ch].GetPan();
            if (pan & 1) left += out;   // L
            if (pan & 2) right += out;  // R
        }
        
        if (i == 0) {  // First sample of this Mix call
            if (mix_call_count == 0) {
                fprintf(stderr, "[OPM Mix] FIRST CALL EVER: left=%d, right=%d, ch_active=%d, channel_mask=%u, volume=%d\n", 
                    left, right, ch_active, channel_mask_, volume_);
            }
            if (mix_call_count % 50 == 0) {
                fprintf(stderr, "[OPM Mix] call#%d[first_sample]: left=%d, right=%d, active_ch=%d, volume=%d, max_L=%d, max_R=%d\n", 
                    mix_call_count, left, right, ch_active, volume_, max_left, max_right);
            }
        }
        
        mix_call_count++;
        if (left != 0 || right != 0) non_zero_count++;
        if (left > max_left) max_left = left;
        if (right > max_right) max_right = right;
        active_ch_count += ch_active;
        
        if (mix_call_count % 10000 == 0) {
            fprintf(stderr, "[OPM Mix] call#%d: non_zero_count=%d, avg_active_ch=%.2f, max_L=%d, max_R=%d\n", 
                mix_call_count, non_zero_count, (double)active_ch_count / 10000.0, max_left, max_right);
            max_left = max_right = 0;
            active_ch_count = 0;
        }

        // Apply volume (volume_ is in 0.5dB steps, negative means attenuation)
        // Positive volume_ value reduces amplitude (right shift)
        if (volume_ > 0) {
            left >>= (volume_ / 2);
            right >>= (volume_ / 2);
        } else if (volume_ < 0) {
            // Negative dB = boost, but we cap at 0 (no boost)
            // Volume is already low due to OPM output being small
        }

        // Clip and store
        // std::clamp is C++17; manual clamp for compatibility
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
    // Simple noise generation
    noise_count_ = (noise_count_ * 13 + 1) & 0xFFFF;
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
