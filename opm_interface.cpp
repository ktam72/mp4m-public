#include "opm_interface.h"

#ifdef USE_FMGEN
#include "Vendor/gamdx/jni/fmgen/opm.h"

// fmgen-based OPM implementation
class FmgenOPM : public OPMInterface {
public:
    FmgenOPM() : opm_(nullptr) {}
    ~FmgenOPM() override { delete opm_; }
    
    void Init(uint32_t clock, uint32_t rate) override {
        opm_ = new FM::OPM();
        opm_->Init(clock, rate);
    }
    
    void SetReg(uint8_t addr, uint8_t data) override {
        if (opm_) opm_->SetReg(addr, data);
    }
    
    void Mix(int16_t* buf, int nsamples) override {
        if (opm_) opm_->Mix(buf, nsamples);
    }
    
    unsigned long GetNextEvent() override {
        if (opm_) return opm_->GetNextEvent();
        return 0xFFFFFFFFul;
    }
    
    void Count(uint32_t us) override {
        if (opm_) opm_->Count(us);
    }
    
private:
    FM::OPM* opm_;
};

#else

#include "Vendor/opm/opm_wrapper.h"

// Original OPM implementation
class OriginalOPM : public OPMInterface {
public:
    OriginalOPM() : wrapper_(nullptr) {}
    ~OriginalOPM() override { delete wrapper_; }
    
    void Init(uint32_t clock, uint32_t rate) override {
        wrapper_ = new OpmWrapper();
        wrapper_->InitWrapper(clock, rate);
    }
    
    void SetReg(uint8_t addr, uint8_t data) override {
        if (wrapper_) wrapper_->SetRegWrapper(addr, data);
    }
    
    void Mix(int16_t* buf, int nsamples) override {
        if (wrapper_) wrapper_->MixWrapper(buf, nsamples);
    }
    
    unsigned long GetNextEvent() override {
        if (wrapper_) return wrapper_->GetNextEventWrapper();
        return 0xFFFFFFFFul;
    }
    
    void Count(uint32_t us) override {
        if (wrapper_) wrapper_->CountWrapper(us);
    }
    
private:
    OpmWrapper* wrapper_;
};

#endif

// Factory implementation
OPMInterface* CreateOPM(bool use_fmgen) {
#ifdef USE_FMGEN
    (void)use_fmgen;  // Compiled with fmgen, ignore flag
    return new FmgenOPM();
#else
    (void)use_fmgen;  // Compiled with original, ignore flag
    return new OriginalOPM();
#endif
}
