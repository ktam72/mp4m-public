#ifndef OPM_WRAPPER_H
#define OPM_WRAPPER_H

#include "ymfm_opm.h"
#include "../gamdx/jni/types.h"

// ymfm (BSD 3-Clause) wrapper providing fmgen-compatible OPM interface.
// ymfm core: Copyright (c) 2021 Aaron Giles - BSD 3-Clause License
// Wrapper: Copyright (c) 2026 ktam72 - Apache 2.0 License

class OpmWrapper : private ymfm::ymfm_interface
{
public:
    OpmWrapper();
    ~OpmWrapper() = default;

    bool Init(uint clock, uint rate, bool filter);
    void Reset();
    void ResetSound() { m_ymfm.reset_sound(); }
    void SetReg(uint addr, uint data);
    uint GetReg(uint addr);
    uint ReadStatus();
    void Mix(int16_t* buffer, int nsamples);
    void SetVolume(int db);
    void SetChannelMask(uint mask);
    uint GetChannelNote(int ch) { return (ch >= 0 && ch < 8) ? m_kc[ch] : 0; }
    int32 GetNextEvent();
    bool Count(int32 us);

    // fmgen 互換タイマーモード切替 (default: true)
    // true  = fmgen 準拠の 64x 高速タイマー (MXDRV 互換)
    // false = ymfm 正規の YM2151 実機相当タイマー
    void SetFmgenTimerCompat(bool enable) { m_fmgen_compat_timer = enable; }

    // Intr callback (overridable by X68OPM)
    virtual void Intr(bool) {}

private:
    // ymfm_interface overrides
    virtual void ymfm_set_timer(uint32_t tnum, int32_t duration_in_clocks) override;
    virtual void ymfm_update_irq(bool asserted) override;

    ymfm::ym2151 m_ymfm;
    uint32_t m_clock;
    uint32_t m_rate;

    // Chip time tracking (in raw chip clocks)
    int64_t m_chip_clocks;
    int64_t m_timer_expire[2];
    bool m_timer_active[2];

    // Channel note cache (key code from regs 0x28-0x2F)
    uint8_t m_kc[8];

    // fmgen compat timer mode flag
    bool m_fmgen_compat_timer;

    // Output volume factor (fmgen compatible)
    int m_fmvolume;
};

#endif // OPM_WRAPPER_H
