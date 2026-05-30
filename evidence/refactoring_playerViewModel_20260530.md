# PlayerViewModel リファクタリング記録

日付: 2026-05-30

## 目的

1. **PlayerViewModel.swift (508行) の分割** — 責務ごとにファイルを分離し保守性を向上
2. **@unchecked Sendable の解消** — Swift 6 移行の布石として MainActor 隔離を徹底

## 変更内容

### PlayerViewModel.swift (508→252行)

- `@unchecked Sendable` を削除し `@MainActor` に変更
- 表示更新ループ → `DisplayUpdateManager` に委譲
- トラック遷移（フェードアウト・曲送り・自動再生） → `TrackTransitionManager` に委譲
- `DispatchQueue.main.async` を全廃し @MainActor に統一
- `nonisolated func playNextFile/playPrevFile` を @MainActor に変更

### DisplayUpdateManager.swift (新規 32行)

- 120fps MainActor 更新ループを管理
- `shouldContinue` + `update` クロージャで柔軟な制御
- ViewModel は `startDisplayUpdates()` でループ開始条件と更新処理のみ提供

### TrackTransitionManager.swift (新規 120行)

- フェードアウト処理（60ステップ、50ms間隔）
- 曲終了時の自動遷移（AUTO/RANDOM/NORMAL）
- 曲送り/曲戻しインデックス計算
- `TrackTransitionManagerDelegate` プロトコルで ViewModel との結合を疎結合化

### MXDRVAudioEngine.swift

- `nonisolated(unsafe) private var mutedChannels` 削除（未使用）

### ThreadSafetyTests.swift

- `@MainActor` 対応に更新（setUp/tearDown に `@MainActor` 付与）
- テスト内容を `testConcurrentChannelAccess` → `testMainActorPropertyAccess` に変更

## 影響範囲

| ファイル | 変更種別 |
|----------|---------|
| ViewModels/PlayerViewModel.swift | リファクタリング（分割＋@MainActor化） |
| Services/DisplayUpdateManager.swift | 新規 |
| Services/TrackTransitionManager.swift | 新規 |
| Services/MXDRVAudioEngine.swift | 未使用プロパティ削除 |
| Tests/ThreadSafetyTests.swift | @MainActor対応 |
| その他全Viewファイル | 変更なし（互換性維持） |

## 検証結果

- Debug ビルド: ✅ 成功
- 全7テスト: ✅ 通過

### 品質スコアカード

| 評価軸 | 評価 | 所見 |
|--------|------|------|
| 効率性 | A | 表示更新ループが DisplayUpdateManager に分離、重複計算排除 |
| 冗長性 | A | 曲送りロジックが TrackTransitionManager に集約 |
| 堅牢性 | A | @MainActor によりコンパイラレベルでスレッド安全性保証 |
| 可読性 | A | 各ファイルの責務が明確 |
| セキュリティ | N/A | 変更なし |
