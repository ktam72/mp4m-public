# MP4M 要件定義書 (Requirements Specification)

MP4M (macOS MDX Player) プロジェクトの機能・非機能要件を管理するドキュメント。
全要件に REQ-ID を採番し、Design フェーズで各コンポーネントへのマッピングを行う。

## REQ-ID 採番規則

- `REQ-XXX`: 大分類 (機能/エンジン/UI/etc.)
- `REQ-XXX-YY`: サブ要件 (詳細仕様)
- 過去の実装に対応する REQ-ID があれば流用、なければ新規採番

## 既存 REQ-ID

| REQ-ID | 概要 | 状態 |
|--------|------|------|
| REQ-001〜005 | 不明 (本セッションでは調査対象外) | 不明 |
| REQ-006 | Nuked OPM エンジン統合 (初版) | **Revert 済み** (2026-05-30、`e52cbe2`) |

---

## REQ-007: Nuked OPM エンジン統合 (再チャレンジ)

| 項目 | 内容 |
|------|------|
| 日付 | 2026-06-03 |
| 種別 | 機能追加 (feat) |
| 優先度 | 中 (CR-002 で KNA03/SC88_036 修正済。Nuked OPM は代替手段として) |
| 関連 | REQ-006 (初版、Revert 済み)、CR-002 (ymfm コア直接修正) |

### 背景

- 過去の REQ-006 (2026-05-30) で Nuked OPM を統合したが、5 つの fix コミットを積み重ねても安定せず、`e52cbe2` で Revert された
- 根本原因: MXDRVG の OPM インターフェースが ymfm/fmgen のサンプル単位 API に最適化されているのに対し、Nuked OPM はサイクル単位 API (`OPM_Clock(chip, *output, *sh1, *sh2, *so)`) であり、両者を抽象化する IOpmEngine に「サイクルモードとサンプルモード両対応」という無理を押し付けた
- 2026-06-03 時点で CR-002 により KNA03/SC88_036 等の主要症状が解決済み。Nuked OPM 統合の緊急度は下がったが、3 番目のエミュレータオプションとして依然価値あり
- ユーザー方針: LGPL 2.1 を取り込むことを許容 (商用利用可能方針は再検討中)

### スコープ

| 含む | 含まない |
|------|---------|
| Nuked OPM ソースの取り込み | 既存 ymfm/fmgen の変更 |
| IOpmEngine のサイクルモード対応拡張 | CR-002 ymfm コア直接修正の取り消し |
| 3 エンジン切替 UI | iOS 対応 |
| LGPL 2.1 ライセンス表示 | パフォーマンス最適化 |
| 既存曲の非回帰テスト | ドキュメント整備 (別途プラン) |
| 検証ログの `evidence/` 保存 | アップストリーム ymfm pull |

### 成功基準

- ビルド成功
- ymfm/fmgen エンジンの動作が CR-002 適用後と同等
- Nuked OPM エンジンで KNA03.MDX が正常再生
- Nuked OPM エンジンで SC88_036.MDX が 20 秒経過後も主旋律が消失しない
- AboutView で 3 ボタン切替 UI が表示される
- LGPL 2.1 ライセンスが AboutView に表示される
- UserDefaults でエンジン設定が永続化される
- エンジン切替時に無音・音切れが発生しない

---

### REQ-007-01: サイクルモード対応 IOpmEngine 拡張

| 項目 | 内容 |
|------|------|
| 概要 | 既存 IOpmEngine を拡張し、Nuked OPM のサイクル単位 API をサポート |
| 背景 | 既存 IOpmEngine は `Mix(int32_t* buffer, int len)` で len サンプル一括生成。Nuked OPM は 1 サイクル = 数サンプル未満のため、サイクルモードで呼ぶ必要 |

**詳細仕様**:

1. 既存 `IOpmEngine` クラスに以下の仮想メソッドを追加 (デフォルト実装で後方互換性確保):
   ```cpp
   // サイクルモードで 1 サイクル進める (Nuked OPM 用)
   virtual void ClockOnce(int32_t* output) { Mix(output, 1); }

   // サイクルモード開始時に呼ぶ (DAC 内部状態の初期化)
   virtual void BeginSampleGeneration() {}

   // サイクルモード終了時に呼ぶ (DAC 内部状態のフラッシュ)
   virtual void EndSampleGeneration() {}
   ```

2. 既存エミュレータ (OpmEngineYmfm, OpmEngineFmgen) はデフォルト実装で動作するため、修正不要

3. `OpmEngineNuked` のみ `ClockOnce` をオーバーライドして `OPM_Clock` を呼び、DAC 出力をサンプルモードと等価な形式で返す

**受け入れ基準**:
- 既存 ymfm/fmgen ビルドが警告なしで通る
- 新メソッドが Nuked OPM で正しく呼ばれる
- サンプルモードで呼んでも Nuked OPM 以外で誤動作しない

**依存**: REQ-007-02, REQ-007-03

---

### REQ-007-02: Nuked OPM ソースの取り込み

| 項目 | 内容 |
|------|------|
| 概要 | `Vendor/NukedOPM/` 配下に Nuked OPM ソース (LGPL 2.1) を配置 |
| 背景 | 商用利用可能方針 (0BSD/Apache 2.0) からの例外として、ユーザー承認のもと LGPL 2.1 を取り込む |

**詳細仕様**:

1. 取得元: <https://github.com/nukeykt/Nuked-OPM> (最新版タグを明示)
2. ファイル配置:
   - `Vendor/NukedOPM/opm.c` (Nuked OPM コア実装、約 2241 行)
   - `Vendor/NukedOPM/opm.h` (Nuked OPM API、289 行)
   - `Vendor/NukedOPM/LICENSE` (LGPL 2.1 全文、504 行)
   - `Vendor/NukedOPM/README.md` (取り込み元と更新日)
3. `.gitignore` に `Vendor/NukedOPM/*.o` 等の中間生成物を追加

**受け入れ基準**:
- ファイルが `Vendor/NukedOPM/` に配置される
- LICENSE 全文が含まれる
- README.md に取得元 URL と取り込み日が記載される
- ビルド時に opm.c がコンパイルされる

**依存**: なし

---

### REQ-007-03: OpmEngineNuked アダプタ実装

| 項目 | 内容 |
|------|------|
| 概要 | `OpmEngineNuked` クラスを実装し、IOpmEngine を継承して Nuked OPM をラップする |
| 背景 | REQ-006 初版で同等の実装があったが、API 不一致のため不安定。REQ-007-01 のサイクルモード対応で改善 |

**詳細仕様**:

1. ファイル: `Vendor/NukedOPM/OpmEngineNuked.h` (過去の 206 行をベースに REQ-007-01 対応で書き直し)
2. 主要メソッド:
   - `Init(clock, rate, filter)`: `OPM_Reset(&m_chip, opm_flags_none)` を呼ぶ
   - `Reset()`: 上記と同じ
   - `SetReg(addr, data)`: 内部レジスタキャッシュ + `OPM_Write(&m_chip, addr, data)` (clock 適用)
   - `ClockOnce(int32_t* output)`: `OPM_Clock(&m_chip, &output[0], &sh1, &sh2, &so)` で DAC サンプル出力
   - `Mix(int32_t* buffer, int len)`: `len` サンプル生成 (ClockOnce を len 回呼ぶ)
   - `GetTimer(TimerId)`: `OPM_ReadCT1`/`OPM_ReadCT2` の結果
   - `GetIRQ()`: `OPM_ReadIRQ` の結果
3. 状態管理: `m_chip` (opm_t 構造体)、`m_clock`, `m_rate`, `m_intr_cb`

**受け入れ基準**:
- コンパイル成功
- 既存 IOpmEngine メソッドすべてが Nuked OPM でも動作
- REQ-007-01 の新メソッドが正しく呼ばれる

**依存**: REQ-007-01, REQ-007-02

---

### REQ-007-04: MXDRVG エンジン切替拡張

| 項目 | 内容 |
|------|------|
| 概要 | エンジン種別 0=ymfm, 1=fmgen, 2=nuked をサポート。切替時の状態保持とスレッドセーフ動作を確保 |
| 背景 | 過去の REQ-006 で 5 つの fix が積み重なった根本原因。REQ-006 失敗を教訓に再設計 |

**詳細仕様**:

1. エンジン種別管理: `g_opm_engine_type` (0/1/2)
2. エンジンインスタンス生成: `MXDRVG_Start` で `g_opm_engine_type` に応じて `new OpmEngineYmfm/Fmgen/Nuked`
3. エンジン切替 API: `MXDRVG_ReplaceEngine(int type)` を新設
   - ミューテックス保護下で `g_engine` を直接差し替え
   - レジスタキャッシュ (`g_opm_regs[256]`) を新エンジンに再生
   - ALG/FB キャッシュ構築
   - タイマー状態リセット
4. 切替時の DAC ミュート: 切替中の無音・音切れ防止のため、サンプル生成を一時的に 0 出力
5. スレッドセーフ: `s_engine_mtx` ミューテックスで保護

**受け入れ基準**:
- エンジン切替時にクラッシュしない
- 切替時に無音・音切れが発生しない (DAC ミュートで吸収)
- 切替後に正常再生が再開される
- 3 エンジンすべてで同じ動作

**依存**: REQ-007-03, REQ-007-08

---

### REQ-007-05: 3 エンジン切替 UI

| 項目 | 内容 |
|------|------|
| 概要 | AboutView の `engineButton` を 3 ボタンに拡張し、ymfm / fmgen / nuked を切替可能に |
| 背景 | 既存 2 ボタン UI を流用拡張 |

**詳細仕様**:

1. ファイル: `MP4M/Views/AboutView.swift`
2. 変更: 既存 2 ボタン (`engineButton("ymfm", type: 0)` と `engineButton("fmgen", type: 1)`) の間に `engineButton("nuked", type: 2)` を追加
3. 選択中エンジンのハイライト維持 (既存実装の流用)
4. UserDefaults キー `"mp4m_opmEngine"` に 0/1/2 を保存
5. デフォルトは 0 (ymfm、CR-002 適用後の安定挙動)

**受け入れ基準**:
- AboutView で 3 ボタンすべてが表示される
- ボタンクリックで対応するエンジンに切替わる
- 選択中エンジンがハイライトされる
- アプリ再起動後も選択が保持される
- デフォルトが ymfm (0) である

**依存**: REQ-007-04

---

### REQ-007-06: LGPL 2.1 ライセンス表示

| 項目 | 内容 |
|------|------|
| 概要 | AboutView に Nuked OPM の LGPL 2.1 ライセンス表示を追加 |
| 背景 | LGPL 2.1 取り込みの義務として作者・ライセンスを明示 |

**詳細仕様**:

1. ファイル: `MP4M/Views/AboutView.swift`
2. 追加: `LicenseRow(name: "Nuked OPM", author: "Nuke.YKT", license: "LGPL 2.1 (with source disclosure)")`
3. LICENSE 全文は別ファイル `MP4M/Resources/THIRD_PARTY_LICENSES/NukedOPM.txt` に配置
4. AboutView から LICENSE 全文への参照リンク設置 (オプション)

**受け入れ基準**:
- AboutView に Nuked OPM ライセンスエントリが追加される
- 作者「Nuke.YKT」が表示される
- LGPL 2.1 と表記される
- ソース開示の旨が明示される

**依存**: REQ-007-02

---

### REQ-007-07: ビルド設定

| 項目 | 内容 |
|------|------|
| 概要 | `project.yml` に NukedOPM フォルダを追加し、ビルドに含める |
| 背景 | 既存 project.yml は gamdx, lzx, ymfm を含むが NukedOPM は含まない |

**詳細仕様**:

1. ファイル: `project.yml`
2. 変更: `sources:` セクションに `Vendor/NukedOPM/opm.c` を追加
3. ヘッダ検索パス: `Vendor/NukedOPM` を追加
4. 確認: `xcodegen generate` でプロジェクト再生成、`xcodebuild` で BUILD SUCCEEDED

**受け入れ基準**:
- xcodegen generate 成功
- xcodebuild BUILD SUCCEEDED
- リンク時に opm.c のシンボル (`OPM_Clock`, `OPM_Write` 等) が解決される

**依存**: REQ-007-02

---

### REQ-007-08: タイマー処理統一

| 項目 | 内容 |
|------|------|
| 概要 | 3 エンジンで同じ CT1/CT2 通知方法を実現し、Nuked OPM でも MDX イベントを正しく処理 |
| 背景 | REQ-006 で `OPM_ReadCT1/CT2` の取扱いが不完全だった。ymfm の Count() との整合性を取る必要あり |

**詳細仕様**:

1. `IOpmEngine` に `GetTimerCount(TimerId id)` 仮想メソッドを追加
   - ymfm: `ymfm_engine_timer_count()` 相当
   - fmgen: `Timer::Get()` 相当
   - nuked: `OPM_ReadCT1` / `OPM_ReadCT2`
2. `MXDRVG_Start` 内のタイマー処理ループで `GetTimerCount` を呼び、CT1/CT2 のオーバーフロー検出
3. 過去 REQ-006 の `ymfm_update_irq → Intr` パターンに Nuked OPM も合わせる
4. `OpmEngineNuked::ReadCT1/CT2` のラッパ追加 (必要に応じて)

**受け入れ基準**:
- Nuked OPM で MDX のタイマーイベント (CSM 等) が正しく発火
- ymfm/fmgen のタイマー動作が変わらない
- CR-002 適用後の ymfm 動作が変わらない

**依存**: REQ-007-01, REQ-007-03

---

### REQ-007-09: 検証 (KNA シリーズ + SC88 シリーズ)

| 項目 | 内容 |
|------|------|
| 概要 | Nuked OPM エンジンで KNA シリーズ・SC88 シリーズの主要曲が正常再生することを検証 |
| 背景 | ユーザー方針「他曲に影響を与える手法は却下」を満たすため、汎用性確認が必須 |

**詳細仕様**:

1. 検証対象曲:
   - **KNA シリーズ**: KNA01, KNA03, KNA03A, KNA04, KNA05, KNA07, KNA09, KNA13A, KNA14_EX, KNA15
   - **SC88 シリーズ**: SC88_017, SC88_033, SC88_036
2. 検証方法:
   - ymp4m 起動 → ファイル選択 → 30 秒再生
   - 3 エンジン切替 → 同じ区間を比較
   - 聴覚 A/B 確認 (ユーザー実施)
   - ymfm ログ取得 (`MP4M_LOG=1 MP4M_YMFM_DEBUG=1`) → A1023 等の異常状態チェック
3. 期待結果:
   - KNA03.MDX: ymfm/fmgen/nuked すべてで中～高音打撃が聞こえる
   - SC88_036.MDX: ymfm/fmgen/nuked すべてで 20 秒経過後も主旋律が消失しない
4. ログ保存: `evidence/nuked-opm-validation/KNA*.log`, `evidence/nuked-opm-validation/SC88_*.log`
5. 結果記録: `evidence/nuked-opm-validation/README.md` (各曲 × 各エンジンの結果表)

**受け入れ基準**:
- KNA シリーズ 10 曲すべてで 3 エンジン正常再生
- SC88 シリーズ 3 曲すべてで 3 エンジン正常再生
- ログが `evidence/nuked-opm-validation/` に保存される
- README に結果表が記載される

**依存**: REQ-007-04, REQ-007-05

---

### REQ-007-10: 非回帰テスト (既存曲)

| 項目 | 内容 |
|------|------|
| 概要 | CR-001, CR-002 適用後の ymfm/fmgen 動作が変わらないことを確認 |
| 背景 | Nuked OPM 統合が既存エンジンに副作用を与えないことを保証 |

**詳細仕様**:

1. 検証対象: KNA シリーズ全 25 曲 (Nuked 検証用の 10 曲 + 残り 15 曲)
2. 検証方法:
   - ymfm エンジンで 25 曲各 30 秒再生
   - 聴覚 A/B 確認 (ユーザー実施)
   - CR-002 適用後と同等であることを確認
3. 異常検知: ログで A1023 永続化や無音状態を特定
4. 結果記録: `evidence/nuked-opm-regression/KNA*.log`

**受け入れ基準**:
- ymfm で KNA シリーズ 25 曲すべてで CR-002 適用後と同等動作
- fmgen で KNA シリーズ 25 曲すべてで正常再生
- 既存曲に副作用なし

**依存**: REQ-007-04

---

## 関連コミット (予定)

- `feat: REQ-007 Nuked OPM エンジン統合 (再チャレンジ)` (1 コミット目)
- `feat: REQ-007-05 3 エンジン切替 UI`
- `feat: REQ-007-06 LGPL 2.1 ライセンス表示`
- `feat: REQ-007-09 検証ログ`

## 想定タイムライン

- Concept: 30 分 (完了)
- Spec: 1 時間 (本ドキュメント作成、完了)
- Design: 1.5 時間
- Coding: 3-4 時間 (複数セッション分割)
- 検証: 1.5 時間
- 合計: 約 8 時間

## 参照ドキュメント

- `docs/ChangeRequest.md` CR-001, CR-002 エントリ
- `evidence/cr-002-resolution.md` 試行履歴
- `evidence/cr-002-side-effects/README.md` SC88 シリーズ副作用チェック
- `technical_docs/CHANGELOG.md` 2.6.0 エントリ
- `technical_docs/CLAUDE.md` 過去 Nuked OPM 統合試行の教訓
