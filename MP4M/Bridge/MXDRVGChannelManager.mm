//
//  MXDRVGChannelManager.mm
//  MXDRVGBridge からチャンネル状態取得・ミュート制御を分離
//

#import "MXDRVGChannelManager.h"
#import "MXDRVGState.h"
#include "../Vendor/gamdx/jni/mxdrvg/mxdrvg.h"

extern MXDRVGState *g_state;

extern "C" {
void OPM_GetChannelStates(MP4MChannelState* states, int max_channels);
int MXDRVG_GetPCM8ChannelMode(int ch);
// F案: ymfm エンベロープ状態・RMS 観測用
int OPM_GetOpEgState(int ch, int opnum);
int OPM_GetOpEgAttenuation(int ch, int opnum);
double OPM_GetCurrentRmsL(void);
double OPM_GetCurrentRmsR(void);
int OPM_IsOpmDebugEnabled(void);
// A案: ymfm の KC レジスタ (0x28-0x2F) を直接読み取り
int OPM_GetRegKc(int ch);
// D案: 任意レジスタ値 (0x00-0xFF) の読み取り
int OPM_GetRegValue(int addr);
}

@implementation MXDRVGChannelManager

+ (void)getChannelStates:(MP4MChannelState *)states {
    if (!states) return;
    memset(states, 0, sizeof(MP4MChannelState) * 16);

    // 例外安全対策：C++ 側（特に OPM_GetChannelStates / GetWork）で例外が起きてもクラッシュさせない
    try {
        // Get OPM channel states (FM 8ch)
        MP4MChannelState opmStates[8];
        memset(opmStates, 0, sizeof(opmStates));

        // Get PCM8 channel states (channels 8-15) from MXDRVG work area
        MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
        MXDRVG_WORK_GLOBAL* globalWork = (MXDRVG_WORK_GLOBAL*)MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL);

        OPM_GetChannelStates(opmStates, 8);

    // OPMチャンネル状態の詳細ログ出力（MP4M_YMFM_DEBUG=1時のみ）
    // ymfm / fmgen 両方で同じフォーマットで出力して比較しやすくする
    if (g_state.ymfmDebugEnabled) {
        g_state.ymfmDebugFrameCount++;
        if (g_state.ymfmDebugFrameCount % g_state.ymfmDebugHighResInterval == 0) {
            NSInteger engineType = [[NSUserDefaults standardUserDefaults] integerForKey:@"mp4m_opmEngine"];
            const char* tag = (engineType == 0) ? "[YMFM_CH]" : "[FMGEN_CH]";
            fprintf(stderr, "%s ", tag);
            for (int i = 0; i < 8; i++) {
                fprintf(stderr, "CH%d:%s(kc=%02X,vol=%02X) ",
                        i+1,
                        opmStates[i].keyOn ? "ON " : "OFF",
                        opmStates[i].keyCode,
                        opmStates[i].volume);
            }
            fprintf(stderr, "\n");

            // A案+D案: ymfm 限定のエンベロープ状態・全体 RMS ログ (全 8ch 拡張)
            // 各 CH の M1/M2/C1/C2 エンベロープ (state, attenuation) + kc の 2 ソース表示 + AR/D1R/D2R/D1L/RR/TL
            if (engineType == 0 && OPM_IsOpmDebugEnabled()) {
                static const char* stateChar[] = {"A", "D", "S", "R"};  // ATTACK/DECAY/SUSTAIN/RELEASE
                fprintf(stderr, "[YMFM_EG]\n");
                for (int ch = 1; ch <= 8; ch++) {
                    fprintf(stderr, "  CH%d:", ch);
                    for (int op = 0; op < 4; op++) {
                        int s = OPM_GetOpEgState(ch, op);
                        int a = OPM_GetOpEgAttenuation(ch, op);
                        if (s < 0 || s > 3) s = 0;
                        fprintf(stderr, " M%d=%s%04d", op + 1, stateChar[s], a);
                    }
                    // D案: AR/D1R/D2R/D1L/RR/TL のオペレーター別値
                    // opoffs = (ch-1)*4 + opnum
                    // AR:  addr 0x80+opoffs, bit 0-4
                    // D1R: addr 0xA0+opoffs, bit 0-4
                    // D2R: addr 0xC0+opoffs, bit 0-4
                    // D1L: addr 0xE0+opoffs, bit 4-7 (MSB)
                    // RR:  addr 0xE0+opoffs, bit 0-3 (LSB)
                    // TL:  addr 0x60+opoffs, bit 0-6
                    int ar[4], d1r[4], d2r[4], d1l[4], rr[4], tl[4];
                    int opoffs_base = (ch - 1) * 4;
                    for (int op = 0; op < 4; op++) {
                        int opoffs = opoffs_base + op;
                        ar[op]  = OPM_GetRegValue(0x80 + opoffs) & 0x1F;
                        d1r[op] = OPM_GetRegValue(0xA0 + opoffs) & 0x1F;
                        d2r[op] = OPM_GetRegValue(0xC0 + opoffs) & 0x1F;
                        int e0 = OPM_GetRegValue(0xE0 + opoffs);
                        d1l[op] = (e0 >> 4) & 0x0F;
                        rr[op]  = e0 & 0x0F;
                        tl[op]  = OPM_GetRegValue(0x60 + opoffs) & 0x7F;
                    }
                    bool has_ar0 = false;
                    for (int op = 0; op < 4; op++) if (ar[op] == 0) { has_ar0 = true; break; }
                    fprintf(stderr, "\n       AR=[%02d,%02d,%02d,%02d] D1R=[%02d,%02d,%02d,%02d] D2R=[%02d,%02d,%02d,%02d] D1L=[%d,%d,%d,%d] RR=[%d,%d,%d,%d] TL=[%02d,%02d,%02d,%02d]%s",
                            ar[0], ar[1], ar[2], ar[3],
                            d1r[0], d1r[1], d1r[2], d1r[3],
                            d2r[0], d2r[1], d2r[2], d2r[3],
                            d1l[0], d1l[1], d1l[2], d1l[3],
                            rr[0], rr[1], rr[2], rr[3],
                            tl[0], tl[1], tl[2], tl[3],
                            has_ar0 ? "  <-- AR=0 DETECTED" : "");
                    int kc_reg = OPM_GetRegKc(ch);
                    int kc_eng = (int)opmStates[ch - 1].keyCode;
                    fprintf(stderr, "\n       kc(reg)=%02X kc(eng)=%02X%s\n",
                            kc_reg, kc_eng,
                            (kc_reg == kc_eng) ? "" : "  <-- MISMATCH");
                }
                // H案: 0x08 KeyOn レジスタの値を表示 (全 CH 共通、最後の 0x08 書き込み値)
                int keyon_reg = OPM_GetRegValue(0x08);
                int ko_ch = keyon_reg & 0x07;        // bit 0-2: channel
                int ko_mask = (keyon_reg >> 3) & 0x0F; // bit 3-6: operator mask
                static const char* opNames[] = {"M1", "M2", "C1", "C2"};
                char mask_str[32];
                mask_str[0] = '\0';
                for (int i = 0; i < 4; i++) {
                    if (ko_mask & (1 << i)) {
                        if (mask_str[0] != '\0') strcat(mask_str, "+");
                        strcat(mask_str, opNames[i]);
                    }
                }
                if (mask_str[0] == '\0') strcpy(mask_str, "(none)");
                fprintf(stderr, "       keyon(reg)=0x%02X: ch=%d mask=%s\n",
                        keyon_reg, ko_ch + 1, mask_str);
                fprintf(stderr, "[YMFM_RMS] L=%5.1fdB R=%5.1fdB\n",
                        OPM_GetCurrentRmsL(), OPM_GetCurrentRmsR());
            }
        }
    }

    // Convert FM channels (0-7)
    for (int i = 0; i < 8; i++) {
        states[i].keyCode = opmStates[i].keyCode;
        states[i].velocity = opmStates[i].velocity;
        states[i].keyOn = opmStates[i].keyOn;
        states[i].volume = opmStates[i].volume;
        states[i].bend = opmStates[i].bend;
        states[i].pan = opmStates[i].pan;
        states[i].keyOffset = opmStates[i].keyOffset;
        states[i].active = opmStates[i].active;
    }

    if (pcmCh) {
        // チャンネルマスクから有効な PCM チャンネル数を判定
        // L001e1a のビット 8-15 が PCM チャンネルに対応
        // bit 8: PCM1, bit 9: PCM2, ..., bit 15: PCM8
        uint16_t channelMask = globalWork ? globalWork->L001e1a : 0;

        for (int i = 0; i < 8; i++) {
            // 配列インデックス i がそのまま PCM1-8ch に対応
            // i=0 → PDX1ch (ch9), i=1 → PDX2ch (ch10), ..., i=7 → PDX8ch (ch16)
            int chIdx = 8 + i;  // Map array index directly to display positions
            int pcmBit = 8 + i;  // PCM channel bit position (bit 8-15)

            // チャンネルマスクでこの PCM チャンネルが有効か確認
            int isChannelEnabled = (channelMask & (1 << pcmBit)) ? 1 : 0;

            UBYTE volatile* S0000 = pcmCh[i].S0000;  // Ptr フィールド

            // 実際に割り当て済みか判定：S0000 ポインタが有効（非ゼロ）
            // S0000 はサンプルデータへのポインタ。ゼロなら割り当てなし
            uint8_t isPlaying = (S0000 != NULL && S0000 != 0) ? 1 : 0;

            if (!isChannelEnabled || !g_state.hasPDX) {
                // このチャンネルはマスクで無効化されている、または PDX がない
                states[chIdx].keyOn = 0;
                states[chIdx].active = 0;
                states[chIdx].volume = 0;
                states[chIdx].velocity = 0;
                continue;
            }

            states[chIdx].keyOn = isPlaying;
            states[chIdx].active = isPlaying;

            // note+D is UWORD, lower bits = note
            uint16_t noteD = pcmCh[i].S0012;
            states[chIdx].keyCode = noteD & 0x7F;
            states[chIdx].keyOffset = 0;

            // PCM パン：PCM8::GetChannelMode() から取得
            // Mode の下位2ビット: bit0=Left, bit1=Right
            // 0b00: Center, 0b01: Left, 0b10: Right, 0b11: Stereo
            int pcm_mode = MXDRVG_GetPCM8ChannelMode(i);
            uint8_t pan_bits = pcm_mode & 0x03;
            if (pan_bits == 0x01) {
                states[chIdx].pan = 0;  // L（左）
            } else if (pan_bits == 0x02) {
                states[chIdx].pan = 2;  // R（右）
            } else if (pan_bits == 0x03) {
                states[chIdx].pan = 3;  // S（ステレオ）
            } else {
                states[chIdx].pan = 1;  // C（中央）
            }

            // Volume: 実際に再生中のときは 100、オフのときは 0
            states[chIdx].volume = isPlaying ? 127 : 0;
            // Spectrum analyzer用：再生中に基づいた固定値を使用（スケール変更を防ぐ）
            states[chIdx].velocity = isPlaying ? 100 : 0;
        }
    }
    } catch (...) {
        #ifdef DEBUG
        fprintf(stderr, "[MXDRVGBridge] EXCEPTION in getChannelStates! Returning empty state.\n");
        #endif
        // すでに memset でゼロクリア済みなので何もしない
    }
}

+ (void)setChannelMute:(int)ch isMuted:(BOOL)isMuted {
    if (ch < 0 || ch >= 16) return;

    if (ch < 8) {
        // FM チャンネル (0-7): YM2151 TL (Total Level) レジスタで制御
        MXDRVG_WORK_CH* fmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_FM);
        if (!fmCh) return;

        if (isMuted) {
            if (!g_state->fmMuteState[ch]) {
                // ミュート開始：元の TL 値を保存して TL=127 に設定
                // FM ワークエリアの S001f (TL) フィールド
                uint8_t currentTL = fmCh[ch].S001f;
                g_state->fmMutedTL[ch] = currentTL;
                g_state->fmMuteState[ch] = 1;
                fmCh[ch].S001f = 127;  // 無音（最大減衰）
            }
        } else {
            if (g_state->fmMuteState[ch]) {
                // ミュート解除：保存した TL 値に復元
                fmCh[ch].S001f = g_state->fmMutedTL[ch];
                g_state->fmMuteState[ch] = 0;
            }
        }
    } else {
        // PCM チャンネル (8-15): volume で制御
        MXDRVG_WORK_CH* pcmCh = (MXDRVG_WORK_CH*)MXDRVG_GetWork(MXDRVG_WORKADR_PCM);
        if (!pcmCh) return;

        int pcmIdx = ch - 8;
        if (pcmIdx < 0 || pcmIdx >= 8) return;

        if (isMuted) {
            if (!g_state->pcmMuteState[pcmIdx]) {
                // ミュート開始：元の volume を保存して 0 に設定
                uint8_t currentVol = pcmCh[pcmIdx].S0022;
                g_state->pcmMutedVol[pcmIdx] = currentVol;
                g_state->pcmMuteState[pcmIdx] = 1;
                pcmCh[pcmIdx].S0022 = 0;  // 無音
            }
        } else {
            if (g_state->pcmMuteState[pcmIdx]) {
                // ミュート解除：保存した volume に復元
                pcmCh[pcmIdx].S0022 = g_state->pcmMutedVol[pcmIdx];
                g_state->pcmMuteState[pcmIdx] = 0;
            }
        }
    }
}

@end
