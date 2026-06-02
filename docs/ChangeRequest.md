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
