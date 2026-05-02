/*
 * C Bridge for OpmDevice C++ implementation
 * Provides C interface to C++ OpmDevice class
 */

#include "backup/opm.h"
#include "opm_wrapper.h"
#include <cstring>
#include <cstdio>

// グローバル OpmDevice インスタンス
static opm::OpmDevice* g_opm_device = nullptr;

// C インターフェース実装

void OPM_InitWrapper(uint32_t clock, uint32_t rate, int filter) {
    (void)filter;

    fprintf(stderr, "[OPM_InitWrapper] ===============================\n");
    fprintf(stderr, "[OPM_InitWrapper] START clock=%u rate=%u\n", clock, rate);

    if (g_opm_device) {
        fprintf(stderr, "[OPM_InitWrapper] Destroying old device: %p\n", (void*)g_opm_device);
        opm::DestroyOpmDevice(g_opm_device);
        g_opm_device = nullptr;
    }

    g_opm_device = opm::CreateOpmDevice();
    fprintf(stderr, "[OPM_InitWrapper] CreateOpmDevice result: %p\n", (void*)g_opm_device);

    if (g_opm_device) {
        bool init_result = g_opm_device->Init(clock, rate);
        fprintf(stderr, "[OPM_InitWrapper] Init result: %d, device=%p\n", init_result, (void*)g_opm_device);
        fprintf(stderr, "[OPM_InitWrapper] Device initialized successfully!\n");
    } else {
        fprintf(stderr, "[OPM_InitWrapper] ERROR: CreateOpmDevice returned nullptr!\n");
    }
    fprintf(stderr, "[OPM_InitWrapper] ===============================\n");
    fflush(stderr);
}

void OPM_SetRegWrapper(uint8_t addr, uint8_t data) {
    static int reg_count = 0;
    if (++reg_count <= 50 || reg_count % 1000 == 0) {
        fprintf(stderr, "[OPM_SetReg] #%d addr=0x%02x data=0x%02x device=%p\n", reg_count, addr, data, (void*)g_opm_device);
    }
    if (g_opm_device) {
        g_opm_device->WriteReg(addr, data);
    } else {
        fprintf(stderr, "[OPM_SetReg] WARNING: device is nullptr!\n");
    }
}

void OPM_MixWrapper(int16_t* buf, int nsamples) {
    static int mix_count = 0;
    mix_count++;

    if (!buf) {
        fprintf(stderr, "[OPM_MixWrapper] #%d ERROR: buf is nullptr\n", mix_count);
        return;
    }

    if (!g_opm_device) {
        fprintf(stderr, "[OPM_MixWrapper] #%d ERROR: g_opm_device is nullptr\n", mix_count);
        memset(buf, 0, nsamples * 2 * sizeof(int16_t));
        return;
    }

    g_opm_device->Mix((opm::Sample*)buf, nsamples);

    if (mix_count <= 10) {
        fprintf(stderr, "[OPM_MixWrapper] #%d nsamples=%d, buf[0]=%d buf[1]=%d buf[2]=%d buf[3]=%d\n",
                mix_count, nsamples, buf[0], buf[1], buf[2], buf[3]);
    }
}

unsigned long OPM_GetNextEventWrapper(void) {
    static int event_count = 0;
    event_count++;

    if (!g_opm_device) {
        if (event_count <= 5) {
            fprintf(stderr, "[OPM_GetNextEvent] #%d ERROR: g_opm_device is nullptr\n", event_count);
        }
        return 0;
    }

    unsigned long result = g_opm_device->GetNextEventTime();

    if (event_count <= 10 || event_count % 1000 == 0) {
        fprintf(stderr, "[OPM_GetNextEvent] #%d result=%lu device=%p\n",
                event_count, result, (void*)g_opm_device);
    }

    return result;
}

void OPM_CountWrapper(uint32_t us) {
    if (g_opm_device) {
        g_opm_device->AdvanceTimers(us);
    }
}

void OPM_GetChannelStates(struct MP4MChannelState* states, int max_channels) {
    if (!g_opm_device || !states) return;

    // C++ の ChannelState を取得
    opm::ChannelState opm_states[8];
    memset(opm_states, 0, sizeof(opm_states));

    g_opm_device->GetChannelStates(opm_states, max_channels < 8 ? max_channels : 8);

    // C構造体にコピー
    for (int i = 0; i < max_channels && i < 8; i++) {
        states[i].keyCode = opm_states[i].keyCode;
        states[i].velocity = opm_states[i].velocity;
        states[i].keyOn = opm_states[i].keyOn;
        states[i].volume = opm_states[i].volume;
        states[i].bend = opm_states[i].bend;
        states[i].pan = opm_states[i].pan;
        states[i].keyOffset = opm_states[i].keyOffset;
        states[i].active = opm_states[i].active;
    }
}

void OPM_SetIntFunc(OPMIntFuncPtr func) {
    // 割り込み関数は MXDRVG 側で管理（未実装）
    (void)func;
}

OPMIntFuncPtr OPM_GetIntFunc(void) {
    return nullptr;
}

opm_t* OPM_GetChipPtr(void) {
    // opm_t 構造体は Nuked OPM 用。C++ 実装では使用しない
    return nullptr;
}
