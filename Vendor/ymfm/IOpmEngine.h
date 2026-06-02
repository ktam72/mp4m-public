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

    // レジスタ値を保持したままオペレーターの実行時状態のみをリセット
    // (m_env_state, m_env_attenuation, m_phase, m_key_state, m_keyon_live)
    virtual void ResetRuntimeState() {}

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

    // ymfm 初回再生音色不良対策 (A-2) で使用。
    // fmgen では no-op、ymfm でのみ内部エンベロープを強制リセットする。
    virtual void ForceReleaseAllChannels() {}

    // F案: ymfm エンベロープ状態・RMS 観測用。
    // fmgen では no-op (デフォルト 0/0.0/false)、ymfm でのみ有効値を返す。
    // ch: 1-8 (FM channel), opnum: 0=M1, 1=M2, 2=C1, 3=C2
    virtual int GetOpEgState(int ch, int opnum) { return 0; }
    virtual int GetOpEgAttenuation(int ch, int opnum) { return 0; }
    virtual double GetCurrentRmsL() { return 0.0; }
    virtual double GetCurrentRmsR() { return 0.0; }
    virtual bool IsOpmDebugEnabled() { return false; }

    // A案: ymfm の KC レジスタ (0x28) を直接読み取る。
    // fmgen は no-op (デフォルト 0)、ymfm でのみ有効値を返す。
    // 8bit 値 (KC[0-7])、KNA03 の CH3 kc=0x0C 問題切り分け用。
    virtual int GetRegKc(int ch) { return 0; }

    // D案: 任意のレジスタ値 (0x00-0xFF) を読み取る。
    // SetReg() で書き込まれた値がキャッシュされている。
    // CH3 M1 の AR (0x88) 等の解析用。
    virtual int GetRegValue(int addr) { return 0; }

    // REQ-007-01: サイクルモード対応 (Nuked OPM 統合用)
    // ymfm/fmgen は Mix() で len サンプル一括生成するサンプル単位 API。
    // Nuked OPM は OPM_Clock() を 1 サイクルずつ呼ぶサイクル単位 API のため、
    // 両者を抽象化する。既存エミュレータはデフォルト実装で動作するため
    // 修正不要。Nuked OPM (OpmEngineNuked) のみオーバーライドする。
    virtual void BeginSampleGeneration() {}
    virtual void EndSampleGeneration() {}
    virtual void ClockOnce(int16_t* output) {}

    // REQ-007-08: タイマー処理統一
    // id: 0 = CT1, 1 = CT2 (YM2151 のタイマー A/B 相当)
    // ymfm: ymfm_engine_timer_count() 経由
    // fmgen: Timer::Get() 経由
    // nuked: OPM_ReadCT1 / OPM_ReadCT2 経由
    virtual uint32_t GetTimerCount(int id) { return 0; }
};

#endif
