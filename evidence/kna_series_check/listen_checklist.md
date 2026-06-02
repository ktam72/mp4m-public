# KNA シリーズ 9 曲試聴チェックリスト

KNA03.MDX で ymfm と fmgen が同じ聞こえ方を実現したことを確認したため、副作用チェックとして同条件の 9 曲を試聴して音の整合性を確認する。

## 試聴対象 9 曲

| # | ファイル | AR=31 回数 | CH3-M1=A1023 回数 | ログパス | 備考 |
|---|---------|-----------|-----------------|---------|------|
| 1 | KNA01.MDX | 0 | 1 | evidence/kna_series_check/KNA01.log | A1023 あるが AR=31 なし |
| 2 | KNA03A.MDX | 51 | 10 | evidence/kna_series_check/KNA03A.log | KNA03 と類似条件 (BOS PDX 共有) |
| 3 | KNA04.MDX | 84 | 1 | evidence/kna_series_check/KNA04.log | AR=31 多い |
| 4 | KNA05.MDX | 34 | 1 | evidence/kna_series_check/KNA05.log | |
| 5 | KNA07.MDX | 60 | 4 | evidence/kna_series_check/KNA07.log | |
| 6 | KNA09.MDX | 14 | 5 | evidence/kna_series_check/KNA09.log | |
| 7 | KNA13A.MDX | 43 | 10 | evidence/kna_series_check/KNA13A.log | KNA13 PDX 使用 |
| 8 | KNA14_EX.MDX | 24 | 1 | evidence/kna_series_check/KNA14_EX.log | |
| 9 | KNA15.MDX | 34 | 1 | evidence/kna_series_check/KNA15.log | |

## 試聴方法

1. **MP4M アプリ起動** → AboutView (左上 `?` ボタン) を開く
2. **`ymfm`** ボタンで ymfm に切り替え
3. 曲を再生
4. 聞こえ方を確認
5. AboutView で **`fmgen`** ボタンで fmgen に切り替え
6. 同じ曲を再生 (ファイルの再ロードが必要な場合あり)
7. ymfm と fmgen の聞こえ方を比較

## 試聴チェックポイント

各曲で以下を確認:

- [ ] **ymfm で音が聞こえる** (基本)
- [ ] **ymfm と fmgen で聞こえ方が同じ** (音程、リズム、音量、音色)
- [ ] **中～高音打撃音が KNA03 と同様に聞こえる** (CH3 相当の音)
- [ ] **音が途切れない、ポップノイズがない** (N+案で keyon タイミング変更したため)
- [ ] **曲の最初から最後まで再生できる** (N+案でロジック変更したため)

## 試聴結果

| ファイル | ymfm OK | fmgen 一致 | 備考 |
|---------|---------|-----------|------|
| KNA01 | | | |
| KNA03A | | | |
| KNA04 | | | |
| KNA05 | | | |
| KNA07 | | | |
| KNA09 | | | |
| KNA13A | | | |
| KNA14_EX | | | |
| KNA15 | | | |

## 修正内容（参考）

- `Vendor/ymfm/ymfm_fm.ipp:733` (N案): `rate <= 62` → `rate < 62` に戻した (ymfm original 維持)
- `Vendor/ymfm/ymfm_fm.ipp:525-537` (N+案): `keyonoff()` で `cache_operator_data()` を呼んでから `start_attack()` を呼ぶ

## 一次情報

- ymfm ログ全 25 ファイル: `evidence/kna_series_check/`
- KNA03.MDX 検証ログ: `kna03_ymfm_v9.log` (本ログ取得後に上記スクリプトで再取得)
- ymfm original glitch 仕様: nukeykt 確認 (AR=62/63 で attack increment スキップ)
