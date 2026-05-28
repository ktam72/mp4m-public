#ifndef OPM_ENGINE_FMGEN_H
#define OPM_ENGINE_FMGEN_H

#include "../../ymfm/IOpmEngine.h"
#include "opm.h"

class OpmEngineFmgen : public IOpmEngine, private FM::OPM
{
public:
    OpmEngineFmgen() : FM::OPM(), m_intr_cb(nullptr) {}

    bool Init(uint32_t clock, uint32_t rate, bool filter) override
    {
        return FM::OPM::Init(clock, rate, filter);
    }

    void Reset() override
    {
        FM::OPM::Reset();
    }

    void ResetSound() override
    {
        // fmgen は再生間で内部状態が適切にリセットされるため不要
    }

    void SetReg(uint32_t addr, uint32_t data) override
    {
        FM::OPM::SetReg(addr, data);
    }

    uint32_t GetReg(uint32_t addr) override
    {
        // FM::OPM に GetReg 実装がないため 0 を返す
        // レジスタ読み出しは mxdrvg_core.h の g_opm_regs で管理
        (void)addr;
        return 0;
    }

    uint32_t ReadStatus() override
    {
        return FM::OPM::ReadStatus();
    }

    void Mix(int16_t* buffer, int nsamples) override
    {
        FM::OPM::Mix(buffer, nsamples);
    }

    void SetVolume(int db) override
    {
        FM::OPM::SetVolume(db);
    }

    void SetChannelMask(uint32_t mask) override
    {
        FM::OPM::SetChannelMask(mask);
    }

    uint32_t GetChannelNote(int ch) override
    {
        return FM::OPM::GetChannelNote(ch);
    }

    int32_t GetNextEvent() override
    {
        return FM::OPM::GetNextEvent();
    }

    bool Count(int32_t us) override
    {
        return FM::OPM::Count(us);
    }

    void SetIntrCallback(IntrCallback cb) override
    {
        m_intr_cb = cb;
    }

    const char* GetEngineName() const override
    {
        return "fmgen";
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
