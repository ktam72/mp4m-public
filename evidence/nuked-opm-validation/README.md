# REQ-007-09 検証チェックリスト: Nuked OPM × KNA/SC88 シリーズ

REQ-007 (Nuked OPM エンジン統合) の検証用チェックリスト。ymp4m を起動し、AboutView の "OPM Engine" ボタン (ymfm / fmgen / nuked) を切り替えて各曲の再生を確認、結果を記録する。

## 検証環境

- ymp4m ビルド: `MP4M.app/Contents/MacOS/MP4M` (Debug, REQ-007 適用版)
- AboutView でエンジン切替 (永続化あり)
- 30 秒程度の試聴を想定
- ymp4m ログ取得はシングルトン制御で second instance 拒否されるため、聴覚 A/B 確認を主とする

## 検証対象曲 (KNA シリーズ 10 曲)

| # | 曲名 | パス | 想定検証ポイント |
|---|------|------|----------------|
| 1 | KNA01.MDX | `MDX/Arsys/Knight_Arms/KNA01.MDX` | FM パーカッション・CH3 AR=31 |
| 2 | KNA03.MDX | `MDX/Arsys/Knight_Arms/KNA03.MDX` | CR-002 修正対象、中～高音打撃 (CH3 AR=31) |
| 3 | KNA03A.MDX | `MDX/Arsys/Knight_Arms/KNA03A.MDX` | KNA03 のバリエーション |
| 4 | KNA04.MDX | `MDX/Arsys/Knight_Arms/KNA04.MDX` | AR=31 使用、CH3 M1 A1023 発生 |
| 5 | KNA05.MDX | `MDX/Arsys/Knight_Arms/KNA05.MDX` | AR=31 使用、CH3 M1 A1023 発生 |
| 6 | KNA07.MDX | `MDX/Arsys/Knight_Arms/KNA07.MDX` | CH3 M1 A1023 4 回発生 |
| 7 | KNA09.MDX | `MDX/Arsys/Knight_Arms/KNA09.MDX` | CH3 M1 A1023 5 回発生 |
| 8 | KNA13A.MDX | `MDX/Arsys/Knight_Arms/KNA13A.MDX` | CH3 M1 A1023 10 回発生 (高頻度) |
| 9 | KNA14_EX.MDX | `MDX/Arsys/Knight_Arms/KNA14_EX.MDX` | AR=31 使用 |
| 10 | KNA15.MDX | `MDX/Arsys/Knight_Arms/KNA15.MDX` | AR=31 使用 |

## 検証対象曲 (SC88 シリーズ 3 曲)

| # | 曲名 | パス | 想定検証ポイント |
|---|------|------|----------------|
| 1 | SC88_017.MDX | `MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_017.MDX` | CR-002 副作用で治った曲 |
| 2 | SC88_033.MDX | `MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_033.MDX` | CR-002 副作用で治った曲 |
| 3 | SC88_036.MDX | `MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_036.MDX` | 20 秒問題 (Ch2/Ch3 主旋律消失) - CR-002 副作用で治った曲 |

## 検証手順

各曲について以下を実行:
1. ymp4m 起動
2. AboutView を開く ("About" ボタン)
3. エンジンを選択 (ymfm / fmgen / nuked)
4. 曲選択ダイアログから対象 .MDX を開く
5. 30 秒程度試聴
6. 結果を以下の表に記録

## 結果記録

### KNA シリーズ

| 曲名 | ymfm | fmgen | nuked | 備考 |
|------|------|-------|-------|------|
| KNA01.MDX | (結果) | (結果) | (結果) | |
| KNA03.MDX | (結果) | (結果) | (結果) | |
| KNA03A.MDX | (結果) | (結果) | (結果) | |
| KNA04.MDX | (結果) | (結果) | (結果) | |
| KNA05.MDX | (結果) | (結果) | (結果) | |
| KNA07.MDX | (結果) | (結果) | (結果) | |
| KNA09.MDX | (結果) | (結果) | (結果) | |
| KNA13A.MDX | (結果) | (結果) | (結果) | |
| KNA14_EX.MDX | (結果) | (結果) | (結果) | |
| KNA15.MDX | (結果) | (結果) | (結果) | |

### SC88 シリーズ

| 曲名 | ymfm | fmgen | nuked | 備考 |
|------|------|-------|-------|------|
| SC88_017.MDX | (結果) | (結果) | (結果) | |
| SC88_033.MDX | (結果) | (結果) | (結果) | |
| SC88_036.MDX | (結果) | (結果) | (結果) | 20 秒経過後も主旋律消失しないか |

## 結果記入凡例

- ✅ OK: 正常再生
- ⚠️ 一部: 一部症状あり (具体を備考に)
- ❌ NG: 無音・音切れ・音色崩れ
- 🔄 検証中: 検証未完了
- N/A: 検証対象外 (ymp4m 起動不可等)

## 検証後のアクション

すべての曲で 3 エンジン OK であれば、REQ-007-10 (非回帰テスト) に進む。
問題があれば、ログ取得 (ymp4m 終了後に再起動) で詳細調査。

## 関連ドキュメント

- `docs/requirements.md` REQ-007-09
- `docs/design-req-007.md` 検証フェーズ
- `evidence/cr-002-resolution.md` CR-002 検証ログ
- `evidence/kna_series_check/` KNA シリーズ 25 曲ログ
- `evidence/cr-002-side-effects/README.md` SC88 シリーズ副作用チェック
