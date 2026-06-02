# REQ-007-10 非回帰テスト: Nuked OPM 統合による ymfm/fmgen への副作用確認

REQ-007 (Nuked OPM エンジン統合) が既存の ymfm/fmgen エンジンに副作用を与えないことを確認する。ymp4m 起動し、ymfm/fmgen 2 エンジンで KNA シリーズ 25 曲を試聴し、CR-002 適用後の動作 (2026-06-03 リリース 2.6.0) と同等であることを確認する。

## 目的

- Nuked OPM 統合 (REQ-007) が ymfm/fmgen のコードに副作用を及ぼしていないことを確認
- KNA シリーズ 25 曲すべてで CR-002 適用後と同等の再生品質を維持
- ユーザー方針「他曲に悪影響を及ぼす手法は却下」の遵守確認

## 検証対象 (KNA シリーズ 25 曲)

KNA シリーズ全曲:

| # | 曲名 | パス | 既知の状態 (CR-002 後) |
|---|------|------|---------------------|
| 1 | KNA00.MDX | `MDX/Arsys/Knight_Arms/KNA00.MDX` | 通常再生 |
| 2 | KNA00A.MDX | `MDX/Arsys/Knight_Arms/KNA00A.MDX` | 通常再生 |
| 3 | KNA01.MDX | `MDX/Arsys/Knight_Arms/KNA01.MDX` | AR=31, CH3-M1=A1023 1回 |
| 4 | KNA02.MDX | `MDX/Arsys/Knight_Arms/KNA02.MDX` | 通常再生 |
| 5 | KNA03.MDX | `MDX/Arsys/Knight_Arms/KNA03.MDX` | CR-002 修正対象、中～高音打撃 |
| 6 | KNA03A.MDX | `MDX/Arsys/Knight_Arms/KNA03A.MDX` | KNA03 類似 |
| 7 | KNA04.MDX | `MDX/Arsys/Knight_Arms/KNA04.MDX` | AR=31, CH3-M1=A1023 1回 |
| 8 | KNA04A.MDX | `MDX/Arsys/Knight_Arms/KNA04A.MDX` | 通常再生 |
| 9 | KNA05.MDX | `MDX/Arsys/Knight_Arms/KNA05.MDX` | AR=31, CH3-M1=A1023 1回 |
| 10 | KNA06.MDX | `MDX/Arsys/Knight_Arms/KNA06.MDX` | 通常再生 |
| 11 | KNA06A.MDX | `MDX/Arsys/Knight_Arms/KNA06A.MDX` | 通常再生 |
| 12 | KNA07.MDX | `MDX/Arsys/Knight_Arms/KNA07.MDX` | AR=31, CH3-M1=A1023 4回 |
| 13 | KNA08.MDX | `MDX/Arsys/Knight_Arms/KNA08.MDX` | 通常再生 |
| 14 | KNA09.MDX | `MDX/Arsys/Knight_Arms/KNA09.MDX` | AR=31, CH3-M1=A1023 5回 |
| 15 | KNA10.MDX | `MDX/Arsys/Knight_Arms/KNA10.MDX` | 通常再生 |
| 16 | KNA11.MDX | `MDX/Arsys/Knight_Arms/KNA11.MDX` | 通常再生 |
| 17 | KNA12.MDX | `MDX/Arsys/Knight_Arms/KNA12.MDX` | 通常再生 |
| 18 | KNA13.MDX | `MDX/Arsys/Knight_Arms/KNA13.MDX` | 通常再生 |
| 19 | KNA13A.MDX | `MDX/Arsys/Knight_Arms/KNA13A.MDX` | AR=31, CH3-M1=A1023 10回 |
| 20 | KNA13_.MDX | `MDX/Arsys/Knight_Arms/KNA13_.MDX` | 通常再生 |
| 21 | KNA14.MDX | `MDX/Arsys/Knight_Arms/KNA14.MDX` | 通常再生 |
| 22 | KNA14_EX.MDX | `MDX/Arsys/Knight_Arms/KNA14_EX.MDX` | AR=31, CH3-M1=A1023 1回 |
| 23 | KNA15.MDX | `MDX/Arsys/Knight_Arms/KNA15.MDX` | AR=31, CH3-M1=A1023 1回 |
| 24 | KNA15A.MDX | `MDX/Arsys/Knight_Arms/KNA15A.MDX` | 通常再生 |
| 25 | KNA16.MDX | `MDX/Arsys/Knight_Arms/KNA16.MDX` | 通常再生 |
| - | KNA16A.MDX | `MDX/Arsys/Knight_Arms/KNA16A.MDX` | 通常再生 |

## 検証手順

各曲について:
1. AboutView で ymfm を選択
2. 曲選択ダイアログから対象 .MDX を開く
3. 30 秒程度試聴
4. 結果を表に記録 (ymfm 列)
5. AboutView で fmgen を選択
6. 同じ曲を試聴
7. 結果を表に記録 (fmgen 列)

## 結果記録

| # | 曲名 | ymfm | fmgen | 備考 |
|---|------|------|-------|------|
| 1 | KNA00.MDX | (結果) | (結果) | |
| 2 | KNA00A.MDX | (結果) | (結果) | |
| ... | ... | ... | ... | |
| 25 | KNA16.MDX | (結果) | (結果) | |

## 結果記入凡例

- ✅ OK: 正常再生 (CR-002 適用後と同等)
- ⚠️ 一部: 一部症状あり (具体を備考に)
- ❌ NG: 明らかに悪化
- 🔄 検証中: 検証未完了
- N/A: 検証対象外

## 成功基準

- KNA シリーズ 25 曲すべてで ymfm/fmgen が「✅ OK」
- 既存曲 (REQ-007 検証用 10 曲 + REQ-007-09 で検証した曲) も含めて「✅ OK」
- CR-002 適用後の動作からの退行なし

## 関連ドキュメント

- `docs/requirements.md` REQ-007-10
- `evidence/nuked-opm-validation/README.md` REQ-007-09 (Nuked OPM 自体の検証)
- `evidence/kna_series_check/` KNA シリーズ CR-002 適用後の基準ログ
- `evidence/cr-002-resolution.md` CR-002 検証ログ
