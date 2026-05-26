#include "opm_wrapper.h"
#include <algorithm>
#include <cmath>
#include <cstring>

OpmWrapper::OpmWrapper() :
    m_ymfm(*this),
    m_clock(0),
    m_rate(0),
    m_chip_clocks(0),
    m_fmgen_compat_timer(true),
    m_fmvolume(16384)
{
    m_timer_expire[0] = 0;
    m_timer_expire[1] = 0;
    m_timer_active[0] = false;
    m_timer_active[1] = false;
    memset(m_kc, 0, sizeof(m_kc));
}

bool OpmWrapper::Init(uint clock, uint rate, bool filter)
{
    m_clock = clock;
    m_rate = rate;
    m_chip_clocks = 0;
    m_timer_active[0] = false;
    m_timer_active[1] = false;

    m_fmgen_compat_timer = true;
    m_ymfm.reset();
    SetVolume(0);
    SetChannelMask(0);
    (void)filter;
    return true;
}

void OpmWrapper::Reset()
{
    m_ymfm.reset();
    m_chip_clocks = 0;
    m_timer_active[0] = false;
    m_timer_active[1] = false;
    memset(m_kc, 0, sizeof(m_kc));
}

void OpmWrapper::SetReg(uint addr, uint data)
{
    if (addr >= 0x100) return;

    if (addr >= 0x28 && addr <= 0x2F)
        m_kc[addr & 7] = (uint8_t)data;

    m_ymfm.write_address((uint8_t)addr);
    m_ymfm.write_data((uint8_t)data);
}

uint OpmWrapper::GetReg(uint addr)
{
    if (addr >= 0x100) return 0;
    if (addr >= 0x28 && addr <= 0x2F)
        return m_kc[addr & 7];
    return 0;
}

void OpmWrapper::Mix(int16_t* buffer, int nsamples)
{
    if (!buffer || nsamples <= 0) return;

    typename ymfm::ym2151::output_data output;

    for (int i = 0; i < nsamples; i++)
    {
        m_ymfm.generate(&output);

		int32_t l = output.data[0];
		int32_t r = output.data[1];

		l = (l * m_fmvolume) >> 14;
		r = (r * m_fmvolume) >> 14;

        buffer[i * 2]     = (int16_t)ymfm::clamp(l, -32768, 32767);
        buffer[i * 2 + 1] = (int16_t)ymfm::clamp(r, -32768, 32767);
    }
}

void OpmWrapper::SetVolume(int db)
{
    db = std::min(db, 20);
    if (db > -192)
        m_fmvolume = (int)(16384.0 * pow(10, db / 40.0));
    else
        m_fmvolume = 0;
}

void OpmWrapper::SetChannelMask(uint mask)
{
    (void)mask;
}

int32 OpmWrapper::GetNextEvent()
{
    if (m_clock == 0) return 0;

    int64_t nearest = 0;
    for (int i = 0; i < 2; i++)
    {
        if (m_timer_active[i])
        {
            int64_t remaining = m_timer_expire[i] - m_chip_clocks;
            if (remaining <= 0)
                return 1;
            if (nearest == 0 || remaining < nearest)
                nearest = remaining;
        }
    }
    if (nearest <= 0) return 0;
    return (int32)(nearest * 1000000LL / m_clock);
}

bool OpmWrapper::Count(int32 us)
{
    if (m_clock == 0 || us <= 0) return false;

    m_chip_clocks += (int64_t)us * m_clock / 1000000LL;

    for (int i = 0; i < 2; i++)
    {
        if (m_timer_active[i] && m_chip_clocks >= m_timer_expire[i])
        {
            m_engine->engine_timer_expired(i);
            // engine_timer_expired 内部で set_reset_status →
            // engine_check_interrupts → ymfm_update_irq が呼ばれ、
            // IRQ 状態変化時のみ Intr() が発火する。
            // さらに Count() 側でもステータスビットがセットされていれば
            // Intr(true) を呼び、fmgen の OPM::Count→GetStatus→Intr
            // と同等の二重通知を実現する。
            uint8_t timer_bit = (i == 0) ? 0x01 : 0x02;
            if (m_ymfm.read_status() & timer_bit)
                Intr(true);
        }
    }
    return true;
}

uint OpmWrapper::ReadStatus()
{
    return m_ymfm.read_status();
}

void OpmWrapper::ymfm_set_timer(uint32_t tnum, int32_t duration_in_clocks)
{
    if (tnum >= 2) return;

    if (duration_in_clocks < 0)
    {
        m_timer_active[tnum] = false;
    }
    else
    {
        // NOTE: 将来 m_fmgen_compat_timer による分岐を入れる場合はここ
        // ymfm のタイマー周期は YM2151 実機準拠:
        //   Timer A: (1024 - regval) * 32 ops * 2 prescale = (1024 - regval) * 64 chip clocks
        //   Timer B: 16 * (256 - regval) * 32 ops * 2 prescale = (256 - regval) * 1024 chip clocks
        // 現在は fmgen 互換補正なし (ymfm 正規タイミング)

        m_timer_expire[tnum] = m_chip_clocks + duration_in_clocks;
        m_timer_active[tnum] = true;
    }
}

void OpmWrapper::ymfm_update_irq(bool asserted)
{
    // engine_timer_expired 内部の engine_check_interrupts から呼ばれる。
    // fmgen の SetStatus → Intr(true) に相当する第一通知。
    if (asserted)
        Intr(true);
}
