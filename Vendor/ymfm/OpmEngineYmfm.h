#ifndef OPM_ENGINE_YMFM_H
#define OPM_ENGINE_YMFM_H

#include "IOpmEngine.h"
#include "opm_wrapper.h"

class OpmEngineYmfm : public IOpmEngine, private OpmWrapper
{
public:
    OpmEngineYmfm() : OpmWrapper(), m_intr_cb(nullptr) {}

    bool Init(uint32_t clock, uint32_t rate, bool filter) override
    {
        return OpmWrapper::Init(clock, rate, filter);
    }

    void Reset() override
    {
        OpmWrapper::Reset();
    }

    void ResetSound() override
    {
        OpmWrapper::ResetSound();
    }

    void ResetRuntimeState() override
    {
        OpmWrapper::ResetRuntimeState();
    }

    void SetReg(uint32_t addr, uint32_t data) override
    {
        OpmWrapper::SetReg(addr, data);
    }

    uint32_t GetReg(uint32_t addr) override
    {
        return OpmWrapper::GetReg(addr);
    }

    uint32_t ReadStatus() override
    {
        return OpmWrapper::ReadStatus();
    }

    void Mix(int16_t* buffer, int nsamples) override
    {
        OpmWrapper::Mix(buffer, nsamples);
    }

    void SetVolume(int db) override
    {
        OpmWrapper::SetVolume(db);
    }

    void SetChannelMask(uint32_t mask) override
    {
        OpmWrapper::SetChannelMask(mask);
    }

    uint32_t GetChannelNote(int ch) override
    {
        return OpmWrapper::GetChannelNote(ch);
    }

    int32_t GetNextEvent() override
    {
        return OpmWrapper::GetNextEvent();
    }

    bool Count(int32_t us) override
    {
        return OpmWrapper::Count(us);
    }

    void SetIntrCallback(IntrCallback cb) override
    {
        m_intr_cb = cb;
    }

    const char* GetEngineName() const override
    {
        return "ymfm";
    }

    void ForceReleaseAllChannels() override
    {
        OpmWrapper::ForceReleaseAllChannels();
    }

protected:
    void Intr(bool irq) override
    {
        if (m_intr_cb)
            m_intr_cb(irq);
    }

private:
    IntrCallback m_intr_cb;
};

#endif
