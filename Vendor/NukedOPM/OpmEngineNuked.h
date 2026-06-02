#ifndef OPM_ENGINE_NUKED_H
#define OPM_ENGINE_NUKED_H

// REQ-007-03: OpmEngineNuked アダプタ実装
// REQ-007-01: サイクルモード対応 (ClockOnce オーバーライド)
// REQ-007-08: タイマー処理統一 (GetTimerCount 実装)

#include "opm.h"
#include "ymfm/IOpmEngine.h"
#include <cstring>
#include <algorithm>
#include <cmath>
#include <cstdint>

class OpmEngineNuked : public IOpmEngine
{
public:
    OpmEngineNuked()
        : m_clock(0), m_rate(0), m_intr_cb(nullptr), m_chip_clocks(0)
        , m_prev_l(0), m_prev_r(0), m_fmvolume(16384)
    {
        std::memset(&m_chip, 0, sizeof(m_chip));
        std::memset(m_regs, 0, sizeof(m_regs));
    }

    bool Init(uint32_t clock, uint32_t rate, bool filter) override
    {
        m_clock = clock;
        m_rate = rate;
        m_chip_clocks = 0;
        m_prev_l = m_prev_r = 0;
        m_fmvolume = 16384;
        std::memset(m_regs, 0, sizeof(m_regs));
        OPM_Reset(&m_chip, opm_flags_none);
        return true;
    }

    void Reset() override
    {
        OPM_Reset(&m_chip, opm_flags_none);
        m_chip_clocks = 0;
        m_prev_l = m_prev_r = 0;
    }

    void ResetSound() override
    {
        // Nuked OPM にはレジスタ値保持したままランタイム状態のみリセット
        // する API がない。setOpmEngine 経路では全レジスタ再生後に
        // ForceReleaseAllChannels() が呼ばれるため、ここでは no-op。
    }

    void ResetRuntimeState() override
    {
        // Nuked OPM はレジスタ状態のみで動作し、別途ランタイム状態を
        // 持たない。YM2151 のエンベロープ/位相はレジスタに依存するため
        // no-op で安全 (ymfm 側の force_full_release 相当の介入は
        // 不要となる)。
    }

    void ForceReleaseAllChannels() override
    {
        // 全 8ch を KeyOff (0x08 + ch)
        for (int ch = 0; ch < 8; ++ch)
            OPM_Write(&m_chip, 0, (uint8_t)(0x08 + ch));
    }

    void SetReg(uint32_t addr, uint32_t data) override
    {
        if (addr >= 0x100) return;
        m_regs[addr] = (uint8_t)data;
        // YM2151 プロトコル: addr → data の順で 2 サイクル消費。
        // 間に OPM_Clock を挟まないと、連続書き込みで addr/data が
        // 入れ替わるリスクがある (d434fa7 過去 fix の対策)。
        OPM_Write(&m_chip, 0, (uint8_t)addr);
        OPM_Write(&m_chip, 1, (uint8_t)data);
    }

    uint32_t GetReg(uint32_t addr) override
    {
        if (addr >= 0x100) return 0;
        return m_regs[addr];
    }

    uint32_t ReadStatus() override
    {
        return OPM_Read(&m_chip, 1);
    }

    // REQ-007-01: サイクルモード (Nuked OPM の API)
    // 1 回の OPM_Clock で 1 スロット進行。32 スロット = 1 内部サンプル。
    // 1 サンプル分の ClockOnce 完了後、DAC 出力を output[0/1] に書き込む。
    // BeginSampleGeneration / EndSampleGeneration は Mix 側で状態を持たない
    // ため no-op のまま。
    void ClockOnce(int16_t* output) override
    {
        if (!output) return;

        static constexpr int SLOTS_PER_SAMPLE = 32;
        int32_t dac[2] = {};
        uint8_t sh1 = 0, sh2 = 0, so = 0;

        for (int s = 0; s < SLOTS_PER_SAMPLE; ++s)
        {
            OPM_Clock(&m_chip, dac, &sh1, &sh2, &so);
            m_chip_clocks++;
        }

        int32_t l = m_chip.dac_output[0] * m_fmvolume / 16384;
        int32_t r = m_chip.dac_output[1] * m_fmvolume / 16384;
        m_prev_l = l;
        m_prev_r = r;

        if (l < -32768) l = -32768; else if (l > 32767) l = 32767;
        if (r < -32768) r = -32768; else if (r > 32767) r = 32767;
        output[0] = (int16_t)l;
        output[1] = (int16_t)r;
    }

    void Mix(int16_t* buffer, int nsamples) override
    {
        if (!buffer || nsamples <= 0) return;
        for (int i = 0; i < nsamples; ++i)
        {
            ClockOnce(&buffer[i * 2]);
        }
    }

    int32_t GetNextEvent() override
    {
        // Nuked OPM はイベント API を持たない。
        // MXDRVG 側では Count() 内の GetTimerCount 経由でタイマー
        // オーバーフローを検出する。0 を返して「次のイベントは即時」と
        // 扱う。
        return 0;
    }

    bool Count(int32_t us) override
    {
        if (us <= 0) return false;
        if (m_clock == 0) return false;

        int64_t cycles = (int64_t)us * m_clock / 1000000LL;
        int32_t dac[2] = {};
        uint8_t sh1 = 0, sh2 = 0, so = 0;
        while (cycles > 0)
        {
            OPM_Clock(&m_chip, dac, &sh1, &sh2, &so);
            m_chip_clocks++;
            cycles--;
        }

        if (OPM_ReadIRQ(&m_chip))
            Intr(true);

        return true;
    }

    // REQ-007-08: タイマー処理統一
    // Nuked OPM は 8bit タイマーカウンタ。YM2151 の CT1/CT2 に相当。
    // id: 0 = CT1, 1 = CT2
    uint32_t GetTimerCount(int id) override
    {
        if (id == 0) return OPM_ReadCT1(&m_chip);
        if (id == 1) return OPM_ReadCT2(&m_chip);
        return 0;
    }

    void SetVolume(int db) override
    {
        if (db > 20) db = 20;
        if (db <= -192) m_fmvolume = 0;
        else m_fmvolume = (int)(16384.0 * pow(10.0, db / 40.0));
    }

    void SetChannelMask(uint32_t mask) override
    {
        (void)mask;
        // Nuked OPM はチャンネルマスク機能を持たない (YM2151 実機にも
        // ない)。no-op で安全。
    }

    uint32_t GetChannelNote(int ch) override
    {
        if (ch >= 0 && ch < 8)
            return m_chip.ch_kc[ch];
        return 0;
    }

    void SetIntrCallback(IntrCallback cb) override
    {
        m_intr_cb = cb;
    }

    const char* GetEngineName() const override
    {
        return "nuked";
    }

protected:
    void Intr(bool irq)
    {
        if (m_intr_cb)
            m_intr_cb(irq);
    }

private:
    opm_t m_chip;
    uint8_t m_regs[256];        // REQ-007-04 のエンジン切替でレジスタ再生用
    uint32_t m_clock;
    uint32_t m_rate;
    int m_fmvolume;
    IntrCallback m_intr_cb;
    int64_t m_chip_clocks;
    int32_t m_prev_l, m_prev_r;
};

#endif // OPM_ENGINE_NUKED_H
