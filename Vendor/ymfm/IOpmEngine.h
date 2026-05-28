#ifndef IOPM_ENGINE_H
#define IOPM_ENGINE_H

#include <stdint.h>

class IOpmEngine
{
public:
    virtual ~IOpmEngine() = default;

    virtual bool Init(uint32_t clock, uint32_t rate, bool filter) = 0;
    virtual void Reset() = 0;
    virtual void ResetSound() = 0;

    virtual void SetReg(uint32_t addr, uint32_t data) = 0;
    virtual uint32_t GetReg(uint32_t addr) = 0;
    virtual uint32_t ReadStatus() = 0;

    virtual void Mix(int16_t* buffer, int nsamples) = 0;

    virtual void SetVolume(int db) = 0;
    virtual void SetChannelMask(uint32_t mask) = 0;

    virtual uint32_t GetChannelNote(int ch) = 0;

    virtual int32_t GetNextEvent() = 0;
    virtual bool Count(int32_t us) = 0;

    using IntrCallback = void (*)(bool);
    virtual void SetIntrCallback(IntrCallback cb) = 0;

    virtual const char* GetEngineName() const = 0;
};

#endif
