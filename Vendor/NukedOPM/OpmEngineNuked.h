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
        int32_t _o[2]={}; uint8_t _s1=0,_s2=0,_so=0;
        OPM_Clock(&m_chip, _o, &_s1, &_s2, &_so);
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

    void Mix(int16_t* buffer, int nsamples)
    {
        if (!buffer || nsamples <= 0) return;
        for (int i = 0; i < nsamples; i++)
        {
            int32_t l = m_prev_l * m_fmvolume / 16384;
            int32_t r = m_prev_r * m_fmvolume / 16384;
            buffer[i * 2]     = (int16_t)(l < -32768 ? -32768 : l > 32767 ? 32767 : l);
            buffer[i * 2 + 1] = (int16_t)(r < -32768 ? -32768 : r > 32767 ? 32767 : r);
        }
    }

    bool Count(int32_t us)
    {
        if (us <= 0) return false;
        int64_t slots = (int64_t)us * m_clock / 1000000LL / 64;
        uint8_t sh1 = 0, sh2 = 0, so = 0;
        int32_t output[2] = {};
        for (int64_t i = 0; i < slots; i++)
        {
            OPM_Clock(&m_chip, output, &sh1, &sh2, &so);
            if ((i & 31) == 31)
            {
                m_prev_l = m_chip.mix[0];
                m_prev_r = m_chip.mix[1];
            }
        }
        if (OPM_ReadIRQ(&m_chip))
            Intr(true);
        return true;
    }

    int32_t GetNextEvent()
    {
        return 0;
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
