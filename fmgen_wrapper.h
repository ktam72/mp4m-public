/*
 * Wrapper to make fmgen OPM API compatible with OpmWrapper interface
 */

#ifndef FMGEN_WRAPPER_H
#define FMGEN_WRAPPER_H

#include <cstdint>
#include "Vendor/gamdx/jni/fmgen/opm.h"

class FmgenOpmWrapper {
public:
    FmgenOpmWrapper() {}
    ~FmgenOpmWrapper() {}

    void InitWrapper(uint32_t clock, uint32_t rate, bool filter = false) {
        opm_.Init(clock, rate, filter);
    }

    void SetVolumeWrapper(int db) {
        opm_.SetVolume(db);
    }

    void SetRegWrapper(uint8_t addr, uint8_t data) {
        opm_.SetReg(addr, data);
    }

    void MixWrapper(int16_t* buf, int nsamples) {
        opm_.Mix((FM::Sample*)buf, nsamples);
    }

    unsigned long GetNextEventWrapper() {
        return opm_.GetNextEvent();
    }

    void CountWrapper(uint32_t us) {
        opm_.Count(us);
    }

    static void (*OPMINT_FUNC)(void);

private:
    FM::OPM opm_;
};

#endif // FMGEN_WRAPPER_H
