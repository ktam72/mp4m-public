# CR-002 副作用チェック (SC88 シリーズ)

CR-002 (`ymfm_fm.ipp:525-537` `keyonoff()` での `cache_operator_data()` 明示呼出 + `ymfm_fm.ipp:733` ymfm original 維持) の修正が、CR-002 対象 (KNA03.MDX) 以外の MDX ファイルにも好影響を与えていることを実機試聴で確認した記録。

## 検証方法

ymp4m (本プロジェクトでビルドした MP4M アプリ) を起動し、ファイル選択 UI から該当 .MDX ファイルを読み込んで再生。聴覚による A/B 確認 (ymfm / fmgen 切替) で「音が正常に出る」「問題の症状が出ない」ことを確認した。

ymp4m の詳細ログ (`MP4M_LOG=1 MP4M_YMFM_DEBUG=1 MP4M_YMFM_HIGHRES=1`) での取得も試みたが、シングルトン制御 (ymp4m が既に起動中のため second instance として拒否) で `lock failed (second instance)` が出力されるのみとなり、ログとしての意味を持たなかった。聴覚確認ができたため、ログ再取得は不要と判断。

## 検証対象曲

| 曲名 | フルパス | 過去の症状 | CR-002 後の状態 |
|------|---------|-----------|----------------|
| SC88_017.MDX | `/Volumes/990Pro_2TB/MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_017.MDX` | 不明 (今回初めて正常確認) | 正常再生 |
| SC88_033.MDX | `/Volumes/990Pro_2TB/MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_033.MDX` | 不明 (今回初めて正常確認) | 正常再生 |
| SC88_036.MDX | `/Volumes/990Pro_2TB/MDX/Falcom/Sorcerian/Original/Swallow_or/SC88_036.MDX` | 約20秒付近の主旋律消失 (Ch2/Ch3) - 2026-05-30 調査で「一旦棚上げ」 | 正常再生 (消失症状なし) |

## 特に重要な確認

**SC88_036.MDX** は 2026-05-30 調査で「ymfm 使用時、約 20 秒付近から主旋律メロディ (主に Ch2/Ch3) が消える、または極端に弱くなる。fmgen では正常。`s=4 (Release) + a=3FF (最大減衰)` のエンベロープ固着頻発」と記録されていた曲。

当時の判断「自動復旧・定期リセット系は他曲に悪影響を及ぼすリスクがあるため一旦棚上げ」を経て、CR-002 で採用した **N+案 (keyonoff での m_cache 更新) + 撤退案 (ymfm original 維持)** が、**SC88_036 の Ch2/Ch3 エンベロープ固着問題も副作用的に解決** したことを意味する。

## 含意

- CR-002 の修正は KNA03.MDX の特定曲対策ではなく、エンベロープジェネレータの根本的な問題 (AR レジスタ書き込み後、KeyOn までの `m_cache` 鮮度問題) に対処していた
- 「他曲に影響を与えない」「特定曲だけ解決する手法を避ける」というユーザー方針が、副作用として **他曲の問題も同時に解決** という結果をもたらした
- ymfm コア直接修正の判断 (`ymfm_fm.ipp:525-537`, `ymfm_fm.ipp:733`) は、修正対象の汎用性において正しかったことが裏付けられた

## ログファイルについて

本ディレクトリに `SC88_*_ymfm.log` ファイルが残っているが、いずれも 6 行の `Singleton lock failed (second instance)` エラーのみであり、ymfm の動作ログではない。証拠としては無効。参考用として残置。
