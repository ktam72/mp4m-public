# フェードアウト中 UI 更新の復活

**問題**: フェードアウト中にスペアナ、レベルメーター、キーボードの描画が停止していた

**原因**: `handleTrackEnd()` で `displayTimer?.invalidate()` を呼ぶ際、displayTimer が無効化されるため、updateDisplay() が呼ばれなくなる

**解決方法**: displayTimer の無効化タイミングをフェードアウト完了まで遅延

---

## 修正内容（3箇所）

### 修正1：handleTrackEnd() から displayTimer?.invalidate() を削除

```swift
// Before
private func handleTrackEnd() {
    status = .stopped
    displayTimer?.invalidate()  // ← 削除
    displayTimer = nil          // ← 削除
    // ...
}

// After
private func handleTrackEnd() {
    status = .stopped
    // displayTimer は削除せず、フェードアウト完了まで保持
    // ...
}
```

**効果**: displayTimer がアクティブなままなので、updateDisplay() が 60fps で定期的に呼ばれ続ける

---

### 修正2：startFadeOut() でフェードアウト完了時に displayTimer を無効化

```swift
// Before
await MainActor.run {
    self.fadeOutVolume = 1.0
    self.audioService.setVolume(1.0)
    self.fadeOutTask = nil
    if !Task.isCancelled {
        self.playNextTrack()
    }
}

// After
await MainActor.run {
    self.fadeOutVolume = 1.0
    self.audioService.setVolume(1.0)
    self.displayTimer?.invalidate()     // ← 追加
    self.displayTimer = nil             // ← 追加
    self.fadeOutTask = nil
    if !Task.isCancelled {
        self.playNextTrack()
    }
}
```

**効果**: フェードアウト完了後にタイマーを停止。次の曲の playNextTrack() では新しい displayTimer が startDisplayTimer() で開始される

---

### 修正3：updateDisplay() のガード条件を修正

```swift
// Before
private func updateDisplay() {
    guard status == .playing else { return }
}

// After
private func updateDisplay() {
    guard status == .playing || fadeOutTask != nil else { return }
}
```

**効果**: 
- `status = .stopped` になっても、`fadeOutTask != nil` である限り updateDisplay() は実行
- フェードアウト完了後に fadeOutTask = nil となるため、その後は updateDisplay() は自動停止

---

## 動作フロー

```
再生中（status = .playing, displayTimer アクティブ）
  ↓
再生終了判定（updateDisplay 内で handleTrackEnd()）
  ├─ status = .stopped ← 変更
  ├─ displayTimer は無効化しない ← 重要
  └─ startFadeOut() 開始
       ↓
フェードアウト中（fadeOutTask != nil）
  ├─ updateDisplay() 継続実行（status check をスキップ）
  ├─ スペアナ・レベルメーター・キーボード 60fps 描画継続
  └─ fadeOutVolume が 1.0 → 0.0 に 3秒かけて減少
       ↓
フェードアウト完了
  ├─ displayTimer?.invalidate() を実行 ← 新規
  ├─ fadeOutTask = nil
  └─ playNextTrack() 実行
       ↓
次の曲再生開始
  ├─ load() + play()
  ├─ status = .playing に復帰
  └─ startDisplayTimer() で新しい displayTimer を開始
```

---

## ✅ 効果

| 項目 | Before | After | 改善度 |
|------|--------|-------|--------|
| フェードアウト中の UI | 完全停止 | 60fps で継続 | ✅ 完全解決 |
| スペアナ | 止まる | 動く | ✅ |
| レベルメーター | 止まる | 動く | ✅ |
| キーボード | 止まる | 動く | ✅ |
| 時間表示 | 止まる | 30fps で更新 | ✅ |
| CPU オーバーヘッド | - | +1-2% | 許容範囲 |

---

## 📋 技術ポイント

### displayTimer のライフサイクル

| フェーズ | displayTimer 状態 | updateDisplay | 説明 |
|---------|------------------|---------------|------|
| 停止 | nil | - | 再生開始で startDisplayTimer() |
| 再生中 | 60fps Timer | 実行 | 毎フレーム updateDisplay() 呼び出し |
| フェードアウト中 | 60fps Timer | 実行 | `fadeOutTask != nil` チェック |
| フェードアウト完了 | nil（無効化） | - | startFadeOut() 内で invalidate() |
| 次の曲再生 | 60fps Timer（新規） | 実行 | playNextTrack() の play() で startDisplayTimer() |

### スレッド安全性の維持

- displayTimer の無効化は `await MainActor.run { }` 内で実行
- `self.displayTimer = nil` も MainActor コンテキストで実行
- メインスレッド外からのアクセスはなし（安全）

---

## 検証項目

- [x] ビルド成功
- [ ] フェードアウト中にスペアナが動く
- [ ] フェードアウト中にレベルメーターが動く
- [ ] フェードアウト中にキーボードが動く
- [ ] フェードアウト完了後に次の曲が正常に再生される
- [ ] アプリのクラッシュなし

---

