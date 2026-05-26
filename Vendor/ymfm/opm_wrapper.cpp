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
    int32_t event_us = (int32)(nearest * 1000000LL / m_clock);
    if (m_timer_active[0] || m_timer_active[1])
        fprintf(stderr, "GNE nearest=%lld event_us=%d\n", (long long)nearest, event_us);
    return event_us;
}

bool OpmWrapper::Count(int32 us)
{
    if (m_clock == 0 || us <= 0) return false;

    int64_t prev = m_chip_clocks;
    m_chip_clocks += (int64_t)us * m_clock / 1000000LL;
    if (m_timer_active[0] || m_timer_active[1])
        fprintf(stderr, "CT us=%d clocks=%lld->%lld TA_exp=%lld TB_exp=%lld\n",
                us, (long long)prev, (long long)m_chip_clocks,
                (long long)m_timer_expire[0], (long long)m_timer_expire[1]);

    for (int i = 0; i < 2; i++)
    {
        if (m_timer_active[i] && m_chip_clocks >= m_timer_expire[i])
        {
            if (i == 0 || i == 1)
                fprintf(stderr, "CT FIRE T%d at clocks=%lld\n", i, (long long)m_chip_clocks);
            m_engine->engine_timer_expired(i);
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
        fprintf(stderr, "ST T%d cancel at clocks=%lld\n", tnum, (long long)m_chip_clocks);
        m_timer_active[tnum] = false;
    }
    else
    {
        int64_t expire = m_chip_clocks + duration_in_clocks;
        fprintf(stderr, "ST T%d dur=%d expire=%lld at=%lld\n", tnum, duration_in_clocks, (long long)expire, (long long)m_chip_clocks);
        m_timer_expire[tnum] = expire;
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
