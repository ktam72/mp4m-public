#ifndef OPM_ENGINE_NUKED_H
#define OPM_ENGINE_NUKED_H

#include "opm.h"
#include "ymfm/IOpmEngine.h"
#include <cstring>
#include <algorithm>

class OpmEngineNuked : public IOpmEngine
{
public:
    OpmEngineNuked()
        : m_clock(0), m_rate(0), m_intr_cb(nullptr), m_chip_clocks(0)
        , m_prev_l(0), m_prev_r(0)
    {
        fprintf(stderr, "[NUKED] Constructor called\n");
        std::memset(&m_chip, 0, sizeof(m_chip));
    }

    ~OpmEngineNuked()
    {
        fprintf(stderr, "[NUKED] Destructor called\n");
    }

    bool Init(uint32_t clock, uint32_t rate, bool filter)
    {
        m_clock = clock;
        m_rate = rate;
        m_chip_clocks = 0;
        m_prev_l = m_prev_r = 0;
        OPM_Reset(&m_chip, opm_flags_none);
        // Init 直後にテストトーンを仕込んで DAC が動作するか確認
        // 任意のチャンネルに単純な音を設定して出力を見る
        SetReg(0x28, 0x41);  // KC ch0 = 0x41 (note)
        SetReg(0x30, 0x14);  // KF ch0 = 0x14
        SetReg(0x38, 0x00);  // PMS/AMS ch0
        SetReg(0x20, 0xc0);  // ALG/FB ch0 = 0, pan both
        SetReg(0x40, 0x01);  // DT1/MUL op0
        SetReg(0x60, 0x00);  // TL op0 = 0 (max vol)
        SetReg(0x80, 0x1f);  // KS/AR op0
        SetReg(0xa0, 0x00);  // AMS/DR op0
        SetReg(0xc0, 0x00);  // DT2/SR op0
        SetReg(0xe0, 0x0f);  // SL/RR op0
        flush_writes();
        int32_t _o[2] = {};
        uint8_t _s1=0,_s2=0,_so=0;
        for (int i = 0; i < 8000; i++)
        {
            OPM_Clock(&m_chip, _o, &_s1, &_s2, &_so);
            if (_o[0] || _o[1])
            {
                fprintf(stderr, "[NUKED Init] DAC non-zero at slot %d: L=%d R=%d\n", i, _o[0], _o[1]);
                break;
            }
        }
        m_prev_l = m_prev_r = 0;
        return true;
    }

    void Reset()
    {
        OPM_Reset(&m_chip, opm_flags_none);
        m_chip_clocks = 0;
        m_prev_l = m_prev_r = 0;
    }

    void ResetSound()
    {
        // Nuked OPM has no standalone reset sound; full reset is OK here
        // because registers are re-written by L_PLAY afterward.
        // Actually for ResetRuntimeState we skip full reset.
    }

    void ResetRuntimeState()
    {
        // Nuked OPM does not persist runtime state separately from registers.
        // Resetting state without clearing registers is not directly supported.
        // We skip it; the Count loop processes correctly due to cycle accuracy.
    }

    void ForceReleaseAllChannels()
    {
        // Key-off all channels
        for (int ch = 0; ch < 8; ++ch)
            OPM_Write(&m_chip, 0, 0x08 + ch);
    }

    void SetReg(uint32_t addr, uint32_t data)
    {
        if (addr >= 0x100) return;
        OPM_Write(&m_chip, 0, (uint8_t)addr);
        OPM_Write(&m_chip, 1, (uint8_t)data);
    }

    uint32_t GetReg(uint32_t addr)
    {
        (void)addr;
        return 0;
    }

    uint32_t ReadStatus()
    {
        return OPM_Read(&m_chip, 1);
    }

    // SetReg でバックツーバックで書き込まれたアドレス/データを
    // OPM_Clock で処理する内部ヘルパ
    void flush_writes()
    {
        if (m_chip.write_a || m_chip.write_d)
        {
            int32_t _o[2]={}; uint8_t _s1=0,_s2=0,_so=0;
            OPM_Clock(&m_chip, _o, &_s1, &_s2, &_so);
        }
    }

    void Mix(int16_t* buffer, int nsamples)
    {
        if (!buffer || nsamples <= 0) return;
        flush_writes();

        // Mix はチップを進めず、前回 Count で生成された DAC 出力をそのまま読む。
        for (int i = 0; i < nsamples; i++)
        {
            int32_t l = m_prev_l * m_fmvolume / 16384;
            int32_t r = m_prev_r * m_fmvolume / 16384;
            buffer[i * 2]     = (int16_t)(l < -32768 ? -32768 : l > 32767 ? 32767 : l);
            buffer[i * 2 + 1] = (int16_t)(r < -32768 ? -32768 : r > 32767 ? 32767 : r);
        }
    }

    int32_t GetNextEvent()
    {
        // Nuked OPM does not expose a direct "time to next event".
        // We approximate by counting clocks until the next timer overflow.
        // For simplicity, return 0 (no pending event / immediate).
        return 0;
    }

    bool Count(int32_t us)
    {
        if (us <= 0) return false;
        flush_writes();

        // OPM_Clock は 1 スロット（= 64 チップサイクル）進める。
        // us マイクロ秒あたりのスロット数 = us * m_clock / 1000000 / 64
        int64_t slots = (int64_t)us * m_clock / 1000000LL / 64;

        uint8_t sh1 = 0, sh2 = 0, so = 0;
        int32_t output[2] = {};
        for (int64_t i = 0; i < slots; i++)
        {
            OPM_Clock(&m_chip, output, &sh1, &sh2, &so);
            if (output[0] || output[1])
            {
                m_prev_l = output[0];
                m_prev_r = output[1];
                break;
            }
        }
        if (m_prev_l || m_prev_r)
            fprintf(stderr, "[NUKED Count] first non-zero L=%d R=%d\n",
                    m_prev_l, m_prev_r);

        if (OPM_ReadIRQ(&m_chip))
            Intr(true);

        return true;
    }

    void SetVolume(int db)
    {
        db = std::min(db, 20);
        if (db > -192)
            m_fmvolume = (int)(16384.0 * pow(10, db / 40.0));
        else
            m_fmvolume = 0;
    }

    void SetChannelMask(uint32_t mask)
    {
        (void)mask;
    }

    uint32_t GetChannelNote(int ch)
    {
        if (ch >= 0 && ch < 8)
            return m_chip.ch_kc[ch];
        return 0;
    }

    void SetIntrCallback(IntrCallback cb)
    {
        m_intr_cb = cb;
    }

    const char* GetEngineName() const
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
    uint32_t m_clock;
    uint32_t m_rate;
    int m_fmvolume = 16384;
    IntrCallback m_intr_cb;
    int64_t m_chip_clocks;
    int32_t m_prev_l, m_prev_r;
};

#endif // OPM_ENGINE_NUKED_H
