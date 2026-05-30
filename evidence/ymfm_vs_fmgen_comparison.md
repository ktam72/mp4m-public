# ymfm 対 fmgen OPM エンジン比較調査報告

## 概要

MP4M では YM2151 (OPM) 音源のエミュレーションエンジンとして ymfm (MAME 採用) と fmgen (XM6 採用) の2つを切り替えて使用できる。
本ドキュメントでは両エンジンの差異を分析し、ラッパーレイヤーで修正可能な問題を特定・修正した経緯を記録する。

## 修正済みの問題 (コミット `aa7ddaa` 時点)

### 1. 初回再生時のみ一部パートが発音されない問題
- **REQ-ID**: REQ-006
- **コミット**: `64c12d7`
- **原因**: `MeasurePlayTime` の Count ループ中、`keyonoff()` → `start_attack()` が未初期化のキャッシュ (`m_cache`) を参照し、一部オペレーターの減衰量 (`m_env_attenuation`) が不適切な値になる。
- **修正**: `OpmWrapper::ResetRuntimeState()` を追加。オペレーター内部状態 (`m_phase`, `m_env_attenuation`, `m_env_state`, `m_key_state`, `m_keyon_live`) のみをリセットし、レジスタ値は保持する。
- **検証**: SC88_003.MDX で 1回目/2回目で同一の音色が得られることを確認。

### 2. タイマー割り込みの二重通知
- **コミット**: `aa7ddaa`
- **原因**: `OpmWrapper::Count()` 内で `engine_timer_expired()` (→ `engine_check_interrupts()` → `ymfm_update_irq()` → `Intr(true)`) に加え、`read_status()` の再チェックから `Intr(true)` が再度呼ばれていた。結果として1タイマー発火あたり MDX シーケンサーが2回進み、MeasurePlayTime の Count ループが早期終了していた。
- **修正**: 後者の `Intr(true)` 呼び出しを削除。
- **検証**: トレースログで ymfm の MeasurePlayTime 処理量が fmgen と同等になったことを確認。

### 3. Pan ビット ($20-$27) の未初期化
- **コミット**: `aa7ddaa`
- **原因**: `ResetRuntimeState()` はレジスタを保持するため、`opm_registers::reset()` (=$20-$27=0xC0) が実行されない。MeasurePlayTime の Count ループ後に Pan=00(MUTE) のチャンネルが発生し、MDX シーケンスの ALG/FB 書き込み時に Pan 保存ロジックが Pan=00 のまま維持してしまう。
- **修正**: `ResetRuntimeState()` 内で `SetReg(0x20+ch, 0xc0 | (fb << 3) | alg)` により、ALG/FB を保持したまま Pan のみ L+R 両方に設定。当初は `SetReg(0x20+ch, 0xc0)` としていたが、ALG=0, FB=0 を上書きしていたため KNA03.MDX で音色が変わってしまうリグレッションが発生。後日修正。
- **検証**: KNA03.MDX 等で一部パートが発音されない問題が改善。

### 4. エンジン切り替え時に実体が再作成されない
- **コミット**: `aa7ddaa`
- **原因**: `MXDRVG_SetOpmEngine()` はグローバル変数 `g_opm_engine_type` の値のみ変更し、`g_engine` インスタンスは再作成されていなかった。UI で fmgen に切り替えたつもりでも ymfm が動作し続けていた。
- **修正**: `MXDRVGBridge.setOpmEngine:` 内で `MXDRVG_SetOpmEngine()` の直後に `resetMXDRVGEngine(44100)` を呼び、旧エンジンを破棄して新エンジンを生成するように修正。

## 実験により改善なしと判断された修正

| # | 仮説 | 変更箇所 | 結果 |
|---|------|---------|------|
| 1 | LFO更新レートを fmgen と同じ8sample毎に間引く | `ymfm_opm.cpp` `clock_noise_and_lfo()` | SC88_003.MDX の伴奏パートに変化なし |
| 2 | ノイズLFSR初期値を fmgen と同じ `0x3039` に変更 | `ymfm_opm.cpp`, `ymfm_opm.h` の `m_fmgen_noise = 0x1234` → `0x3039` | SC88_037.MDX のノイズに変化なし（該当曲違い） |
| 3 | `start_attack()` で `m_env_attenuation` を常に `0x3ff` にリセット | `ymfm_fm.ipp` `start_attack()` | かえって悪化 |

## 受理された残差異

以下の差異は ymfm コアエンジンの内部実装に起因し、ラッパーレイヤーでの修正は困難と判断。

| 領域 | fmgen | ymfm | 影響 |
|------|-------|------|------|
| LFO更新レート | 8 samples 毎 | 毎 sample | PM/AMモジュレーション波形のなめらかさ |
| エンベロープoff状態 | `off` 明示的停止状態あり | `EG_RELEASE` + 閾値判定 (`EG_QUIET=0x380`) | リリース末尾の減衰テール長 |
| 出力精度 | 16bit中間クリップあり | 32bitフル精度 | 複数チャンネル累積時のクリッピング差 |
| ノイズLFSR初期値 | `0x3039` | `0x1234` | ノイズシーケンスの位相差（実機との一致度は不明） |
| エンベロープレート | fmgen独自テーブル | ymfm独自テーブル | アタック/ディケイ/リリースの時間差 |
| 発振器 | fmgen独自 | ymfm独自 | ピッチ/周波数変調の微差 |

## 検証に使用した MDX ファイル

| ファイル | 特徴 | 確認内容 |
|---------|------|---------|
| SC88_003.MDX | FMのみ、伴奏+メロディ | 初回発音抜け、Pan問題 |
| SC88_017.MDX | FMのみ、ノイズ使用 | ノイズ音色差（→実際はノイズ未使用だった） |
| SC88_036.MDX | FMのみ、20秒過ぎで主旋律停止 | タイミング依存の発音抜け |
| SC88_037.MDX | FMのみ | ノイズ聞き比べ（→対象曲違い） |
| SC88_044.MDX | FMのみ | 初回発音抜け（初期分析時） |
| KNA03.MDX | FMのみ | Pan問題（初期分析時） |

## 結論

ymfm は MAME で実機検証済みのコアであり、実機 YM2151 に忠実な動作をする。fmgen との差異は両エミュレータの設計上の違いによるものであり、どちらかが「正しい」とは一概に言えない。ラッパーレイヤーで修正可能なバグ（二重 Intr、Pan 未初期化、エンジン切替不備等）は全て修正済み。
