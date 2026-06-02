# CR-002: KNA03.MDX の中～高音打撃を ymfm で聞こえるようにする

| 項目       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 日付       | 2026-06-03                                                           |
| 種別       | バグ修正 (fix)                                                       |
| 対象       | `Vendor/ymfm/ymfm_fm.ipp` (N+案)                                     |
| 背景       | KNA03.MDX 再生時に中～高音打撃（CH3 相当）が曲の最初から最後まで聞こえない |
| 影響範囲   | ymfm コアの `keyonoff()` 経路のみ。fmgen には影響なし                 |
| 設計       | N+案: `keyonoff()` で `cache_operator_data()` を明示呼出 → `start_attack()` |

## 症状詳細

- 対象ファイル: `KNA03.MDX` (Arsys, Knight Arms)
- エンジン: ymfm
- 症状: 中～高音打撃（CH3 相当、AR=31 (rate=62/63) を使用）が無音
- fmgen エンジンでは正常再生

## 試行履歴

### H1〜H10: 仮説検証（F案〜K案ログ拡張）

| 案 | 内容 | 結果 |
|----|------|------|
| F案 | `[YMFM_EG]` (CH1+CH3+CH7 状態) + `[YMFM_RMS]` (全体 L/R dB) ログ追加 | CH3 M1 が A1023 維持で m_env_attenuation=1023 のまま動かないことを特定 |
| A案 | 全 8ch EG ログ拡張 | CH1/CH3/CH4 などで A1023 頻発を確認 |
| D案 | `OPM_GetRegValue()` で EG ログに AR/D1R/D2R/D1L/RR/TL 表示 | CH3 M1 の AR=31 を確認 |
| H案 | 0x08 KeyOn レジスタ値表示 | 0x7A (CH3 KeyOn all ops) が継続的に書き込まれていることを確認 |
| K案 | `OpmWrapper::SetReg` で 0x08 書き込みを時系列ログ | MXDRVG → ymfm の経路で確実に keyonoff() が呼ばれていることを確認 |

### N案: ymfm コア修正（撤回）

- 修正: `ymfm_fm.ipp:721` `if (rate < 62)` → `if (rate <= 62)`
- 目的: AR=62/63 で attack increment をスキップしない
- **撤回理由**: 副作用判明
  - `start_attack()` で `m_env_attenuation = 0` にジャンプ直後の `clock_envelope()` で攻撃段階の increment 計算が実行され、`~0 * increment >> 4` が負の値になり wrap → 0x400 以上で 0x3FF (1023) にクランプ → **A1023 維持問題が再発**
- 撤退案: `rate < 62` に戻す（ymfm original 維持）

### N+案: keyonoff での m_cache 更新

- 修正: `ymfm_fm.ipp:525-537` `keyonoff()` 内で `cache_operator_data()` を呼んでから `start_attack()`
- 目的: KeyOn 時点で `m_cache.eg_rate[EG_ATTACK]` を最新化
- 効果: AR=31 で `start_attack()` 内の `m_cache.eg_rate[EG_ATTACK] >= 62` ジャンプ条件を満たす

### 撤退案（最終採用）

- 変更 1: ymfm_fm.ipp:733 `rate <= 62` → `rate < 62` (N案の取り消し、ymfm original 維持)
- 変更 2: ymfm_fm.ipp:525-537 N+案を維持
- 期待動作: AR=31 で `m_cache.eg_rate[EG_ATTACK] >= 62` true → `m_env_attenuation = 0` ジャンプ → ymfm original の `rate < 62` で攻撃段階 increment スキップ → m_env_attenuation = 0 維持 → 次の `clock_envelope()` で `m_env_state == EG_ATTACK && m_env_attenuation == 0` → EG_DECAY 遷移 → EG_SUSTAIN (D1L=0) へ正常遷移

## 検証結果

### KNA03.MDX 実機試聴

- **ymfm**: FMGEN と同じ聞こえ方（中～高音打撃が聞こえる）
- **fmgen**: 正常（既存動作）

### KNA シリーズ一括ログ取得

25 ファイル全曲で ymfm ログ取得し、AR=31 使用曲と CH3-M1=A1023 発生曲を特定。

詳細: `evidence/kna_series_check/summary2.log` および `listen_checklist.md`

| カテゴリ | 曲数 |
|---------|------|
| AR=31 使用曲 | 22 曲 |
| CH3-M1=A1023 発生曲 | 10 曲 |
| 試聴確認済み | KNA03 (成功) |
| 試聴未確認 | KNA01, KNA03A, KNA04, KNA05, KNA07, KNA09, KNA13A, KNA14_EX, KNA15 |

## 変更ファイル

| ファイル | 変更内容 |
|----------|----------|
| `Vendor/ymfm/ymfm_fm.ipp` | line 525-537 N+案追加、line 733 N案取り消し（`rate < 62` 維持） |
| `Vendor/ymfm/IOpmEngine.h` | F/A/D 案: `GetOpEgState`, `GetOpAttenuation`, `GetCurrentRmsL/R`, `IsOpmDebugEnabled`, `GetRegKc`, `GetRegValue` メソッド追加 |
| `Vendor/ymfm/opm_wrapper.h` | 同上メソッド宣言、`m_regdata[256]` キャッシュ追加 |
| `Vendor/ymfm/opm_wrapper.cpp` | SetReg で `m_regdata` キャッシュ + K案ログ、Mix() で RMS 累積 |
| `Vendor/ymfm/OpmEngineYmfm.h` | 6 メソッド override（OpmWrapper 委譲） |
| `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h` | 6 個の C インターフェース `OPM_Get*` 追加（`s_engine_mtx.try_lock()` パターン） |
| `MP4M/Bridge/MXDRVGChannelManager.mm` | extern 宣言 + `[YMFM_EG]` ログ統合 |

## 一次情報

- KNA03 ログ（最新）: `kna03_ymfm_v9.log`（17,206 行、798KB）— `git ignore` 済み
- KNA シリーズ一括ログ: `evidence/kna_series_check/KNA*.log`（25 ファイル、summary2.log に集計）
- ymfm original glitch 仕様: AR=62/63 で attack increment スキップ（nukeykt 確認）
- AGENTS.md: ソースコード生成時のルール、Spec-Driven Workflow、2-Layer Quality Gate

## 関連コミット

- fix: CR-002 KNA03.MDX の中～高音打撃を ymfm で聞こえるようにする
