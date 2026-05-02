#ifndef OPM_WRAPPER_H
#define OPM_WRAPPER_H

#include <stdint.h>
#include "opm.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MP4MChannelState {
    uint8_t keyCode;
    uint8_t keyOn;
    uint8_t volume;
    uint8_t velocity;
    int16_t bend;
    uint8_t pan;
    uint8_t keyOffset;
    uint8_t active;
} MP4MChannelState;

// OPM interrupt callback type
typedef void (*OPMIntFuncPtr)(void);

// Initialize OPM wrapper
void OPM_InitWrapper(uint32_t clock, uint32_t rate, int filter);

// Write OPM register
void OPM_SetRegWrapper(uint8_t addr, uint8_t data);

// Mix audio samples
void OPM_MixWrapper(int16_t* buf, int nsamples);

// Get next event time in microseconds
unsigned long OPM_GetNextEventWrapper(void);

// Count time (timer advance)
void OPM_CountWrapper(uint32_t us);

// Get channel states
void OPM_GetChannelStates(struct MP4MChannelState* states, int max_channels);

// Set global interrupt callback
void OPM_SetIntFunc(OPMIntFuncPtr func);

// Get global interrupt callback
OPMIntFuncPtr OPM_GetIntFunc(void);

// Get pointer to opm_t instance (for MXDRVG_GetWork)
opm_t* OPM_GetChipPtr(void);

#ifdef __cplusplus
}
#endif

#endif // OPM_WRAPPER_H
