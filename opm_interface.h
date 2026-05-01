/*
 * OPM interface for testing both original and fmgen implementations
 * This allows CLI to switch between implementations for comparison
 */

#ifndef OPM_INTERFACE_H
#define OPM_INTERFACE_H

#include <cstdint>

// Abstract OPM interface
class OPMInterface {
public:
    virtual ~OPMInterface() = default;
    
    virtual void Init(uint32_t clock, uint32_t rate) = 0;
    virtual void SetReg(uint8_t addr, uint8_t data) = 0;
    virtual void Mix(int16_t* buf, int nsamples) = 0;
    virtual unsigned long GetNextEvent() = 0;
    virtual void Count(uint32_t us) = 0;
};

// Factory function to create OPM implementation
OPMInterface* CreateOPM(bool use_fmgen);

#endif // OPM_INTERFACE_H
