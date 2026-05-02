/*
 * Nuked-OPM C wrapper for MXDRVG compatibility
 * Copyright (c) 2026
 */

#include "opm_wrapper.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdio.h>

static opm_t g_chip;
static uint32_t g_clock = 0;
static uint32_t g_sample_rate = 0;
static OPMIntFuncPtr g_int_func = NULL;

void OPM_InitWrapper(uint32_t clock, uint32_t rate, int filter) {
    (void)filter;
    fprintf(stderr, "[opm_wrapper] OPM_InitWrapper called! clock=%u rate=%u\n", clock, rate);
    g_clock = clock;
    g_sample_rate = rate;
    OPM_Reset(&g_chip, 0);
    fprintf(stderr, "[opm_wrapper] OPM_Reset done, chip initialized\n");
    fflush(stderr);
}

void OPM_SetRegWrapper(uint8_t addr, uint8_t data) {
    static int reg_count = 0;
    if (++reg_count <= 100 || reg_count % 1000 == 0 || addr == 0x08) {
        fprintf(stderr, "[OPM_SetReg] #%d addr=0x%02x data=0x%02x\n", reg_count, addr, data);
    }
    if (addr == 0x08 && data != 0) {
        fprintf(stderr, "[OPM_SetReg] !!! KEY-ON detected: addr=0x%02x data=0x%02x (channels=%d)\n", addr, data, data & 0x07);
    }
    OPM_Write(&g_chip, 0, addr);
    OPM_Write(&g_chip, 1, data);
}

void OPM_MixWrapper(int16_t* buf, int nsamples) {
    static int mix_count = 0;
    mix_count++;

    if (mix_count <= 5) {
        fprintf(stderr, "[OPM_MixWrapper] #%d nsamples=%d clock=%u rate=%u\n",
                mix_count, nsamples, g_clock, g_sample_rate);
    }

    for (int i = 0; i < nsamples; i++) {
        if (g_clock == 0 || g_sample_rate == 0) {
            buf[i*2 + 0] = 0;
            buf[i*2 + 1] = 0;
            continue;
        }

        uint32_t cycles_per_sample = g_clock / g_sample_rate;
        if (cycles_per_sample == 0) cycles_per_sample = 1;

        int32_t sample_l = 0, sample_r = 0;
        uint32_t cycle_count = 0;

        for (uint32_t c = 0; c < cycles_per_sample; c++) {
            int32_t output[2] = {0, 0};
            uint8_t sh1, sh2, so;
            OPM_Clock(&g_chip, output, &sh1, &sh2, &so);
            sample_l += output[0];
            sample_r += output[1];
            cycle_count++;
        }

        if (cycle_count > 0) {
            sample_l /= (int32_t)cycle_count;
            sample_r /= (int32_t)cycle_count;
        }

        buf[i*2 + 0] = (int16_t)(sample_l > 32767 ? 32767 : (sample_l < -32768 ? -32768 : sample_l));
        buf[i*2 + 1] = (int16_t)(sample_r > 32767 ? 32767 : (sample_r < -32768 ? -32768 : sample_r));
    }

    if (mix_count <= 5) {
        fprintf(stderr, "[OPM_MixWrapper] #%d done: buf[0]=%d buf[1]=%d\n",
                mix_count, buf[0], buf[1]);
    }
}

unsigned long OPM_GetNextEventWrapper(void) {
    // Always return 0 to force interrupt processing
    // This makes MXDRVG_GetPCM() call OPMINTFUNC() every time
    return 0;
}

void OPM_CountWrapper(uint32_t us) {
    (void)us;
    // Nothing to do - GetNextEventWrapper always returns 0
}

void OPM_GetChannelStates(struct MP4MChannelState* states, int max_channels) {
    for (int i = 0; i < max_channels && i < 8; i++) {
        states[i].keyCode = g_chip.ch_kc[i];
        uint8_t kon = 0;
        for (int slot = i; slot < 32; slot += 8) {
            if (g_chip.kon[slot] || g_chip.mode_kon[slot]) {
                kon = 1;
                break;
            }
        }
        states[i].keyOn = kon;
        states[i].volume = 0;
        states[i].velocity = 0;
        states[i].bend = 0;
        states[i].pan = 0;
        states[i].keyOffset = 0;
        states[i].active = kon;
    }
}

void OPM_SetIntFunc(OPMIntFuncPtr func) {
    g_int_func = func;
}

OPMIntFuncPtr OPM_GetIntFunc(void) {
    return g_int_func;
}

opm_t* OPM_GetChipPtr(void) {
    return &g_chip;
}
