# Nuked OPM

YM2151 (OPM) FM 音源エミュレータ。

## 取り込み元

- **リポジトリ**: <https://github.com/nukeykt/Nuked-OPM>
- **作者**: Nuke.YKT
- **ライセンス**: GNU Lesser General Public License v2.1 (LGPL 2.1)
- **取り込み日**: 2026-06-03
- **取り込みブランチ**: `master`

## ファイル

| ファイル | 行数 | 用途 |
|---------|------|------|
| `opm.h` | 289 | Nuked OPM API 宣言 |
| `opm.c` | 2241 | Nuked OPM コア実装 |
| `LICENSE` | 504 | LGPL 2.1 全文 |
| `OpmEngineNuked.h` | (MP4M 側で追加) | `IOpmEngine` アダプタ |

## 取り込み方針

**直接取り込み** (submodule/submodule 等は使用しない)。

`opm.c` および `opm.h` は Nuked-OPM のオリジナルをそのまま配置し、MP4M 側では編集しない。MP4M 側の拡張は `OpmEngineNuked.h` (アダプタ層) で行う。

## upstream 取り込み手順 (将来)

将来 Nuked-OPM の最新版を取り込む際は、以下の手順を推奨:

1. <https://github.com/nukeykt/Nuked-OPM/commits/master> で最新リリースを確認
2. 現行の `opm.c` / `opm.h` のファイルハッシュを保存 (比較用)
3. 最新版をダウンロードして上書き
4. `OpmEngineNuked.h` の `IOpmEngine` インターフェースと整合性を確認
5. ビルド成功 + ymfm/fmgen で非回帰テスト実施

## 関連ドキュメント

- `docs/requirements.md` REQ-007 (統合要件定義)
- `docs/design-req-007.md` REQ-007 設計書
- `docs/ChangeRequest.md` (将来統合時の変更記録)
- `MP4M/Resources/THIRD_PARTY_LICENSES/NukedOPM.txt` (アプリ同梱用 LICENSE)
