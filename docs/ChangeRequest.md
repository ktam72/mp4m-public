# Change Request Log

## CR-001: FileSelector の PATH 文字列を選択可能にする

| 項目       | 内容                                                 |
| ---------- | ---------------------------------------------------- |
| 日付       | 2026-06-02                                           |
| 種別       | 機能追加 (feat)                                      |
| 対象       | `MP4M/Views/FileSelectorView.swift`                  |
| 背景       | デバッグ時に表示中のディレクトリパスをコピペしたい   |
| 影響範囲   | View のみ、Model / ViewModel 変更なし                |
| 設計       | 案B: 選択 + Copy + ツールチップ                      |
| コピー動線 | 右クリックメニュー                                    |

### 変更内容

- PATH 表示 Text に `.textSelection(.enabled)` を追加し範囲選択を可能に
- ホバー時の `.help()` でフルパスをツールチップ表示（truncation の補完）
- 右クリックメニューに「Copy Path」を追加（NSPasteboard 経由）

### 非対象

- FileRowView の選択挙動
- 表示スタイル（フォント・色・truncation）
- PlayerViewModel / FileBrowserViewModel

### 検証

- ビルド成功
- 実機/シミュレータで3機能（ドラッグ選択 / ツールチップ / Copy→paste）確認

### 関連コミット

- feat: CR-001 FileSelector の PATH 文字列を選択可能に

## CR-002: KNA03.MDX の中～高音打撃を ymfm で聞こえるようにする

| 項目       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 日付       | 2026-06-03                                                           |
| 種別       | バグ修正 (fix)                                                       |
| 対象       | `Vendor/ymfm/ymfm_fm.ipp` (`keyonoff()` 経路)                        |
| 背景       | KNA03.MDX 再生時に中～高音打撃（CH3 相当）が曲の最初から最後まで聞こえない |
| 影響範囲   | ymfm コアの `keyonoff()` 経路のみ。fmgen には影響なし                 |
| 設計       | N+案: `keyonoff()` で `cache_operator_data()` を明示呼出 → `start_attack()` |

### 症状詳細

- 対象ファイル: `KNA03.MDX` (Arsys, Knight Arms)
- エンジン: ymfm
- 症状: 中～高音打撃（CH3 相当、AR=31 (rate=62/63) を使用）が無音
- fmgen エンジンでは正常再生

### 試行履歴

#### H1〜H10: 仮説検証（F案〜K案ログ拡張）

| 案 | 内容 | 結果 |
|----|------|------|
| F案 | `[YMFM_EG]` (CH1+CH3+CH7 状態) + `[YMFM_RMS]` (全体 L/R dB) ログ追加 | CH3 M1 が A1023 維持で m_env_attenuation=1023 のまま動かないことを特定 |
| A案 | 全 8ch EG ログ拡張 | CH1/CH3/CH4 などで A1023 頻発を確認 |
| D案 | `OPM_GetRegValue()` で EG ログに AR/D1R/D2R/D1L/RR/TL 表示 | CH3 M1 の AR=31 を確認 |
| H案 | 0x08 KeyOn レジスタ値表示 | 0x7A (CH3 KeyOn all ops) が継続的に書き込まれていることを確認 |
| K案 | `OpmWrapper::SetReg` で 0x08 書き込みを時系列ログ | MXDRVG → ymfm の経路で確実に keyonoff() が呼ばれていることを確認 |

#### N案: ymfm コア修正（撤回）

- 修正: `ymfm_fm.ipp:721` `if (rate < 62)` → `if (rate <= 62)`
- 目的: AR=62/63 で attack increment をスキップしない
- **撤回理由**: 副作用判明
  - `start_attack()` で `m_env_attenuation = 0` にジャンプ直後の `clock_envelope()` で攻撃段階の increment 計算が実行され、`~0 * increment >> 4` が負の値になり wrap → 0x400 以上で 0x3FF (1023) にクランプ → **A1023 維持問題が再発**
- 撤退案: `rate < 62` に戻す（ymfm original 維持）

#### N+案: keyonoff での m_cache 更新（最終採用）

- 修正: `ymfm_fm.ipp:525-537` `keyonoff()` 内で `cache_operator_data()` を呼んでから `start_attack()`
- 目的: KeyOn 時点で `m_cache.eg_rate[EG_ATTACK]` を最新化
- 効果: AR=31 で `start_attack()` 内の `m_cache.eg_rate[EG_ATTACK] >= 62` ジャンプ条件を満たす
- 組み合わせ: N案の取り消し（`rate < 62` 維持）と組み合わせて、ymfm original の攻撃段階 increment スキップ仕様を尊重

### 変更内容

- `Vendor/ymfm/ymfm_fm.ipp:733` `if (rate <= 62)` → `if (rate < 62)` (N案の取り消し)
- `Vendor/ymfm/ymfm_fm.ipp:525-537` N+案: `keyonoff()` で `cache_operator_data()` 明示呼出

### 検証

- ビルド成功
- KNA03.MDX 実機試聴: ymfm と fmgen で同じ聞こえ方
- KNA シリーズ 25 ファイルログ取得: AR=31 使用曲 22 曲、CH3-M1=A1023 発生曲 10 曲
- 詳細: `evidence/cr-002-resolution.md`、`evidence/kna_series_check/`

### 非対象

- fmgen 側（既に正常動作）
- 他社 MDX での副作用チェック（次のセッションで継続）

### 関連コミット

- fix: CR-002 KNA03.MDX の中～高音打撃を ymfm で聞こえるようにする
