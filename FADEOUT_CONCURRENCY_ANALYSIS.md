# フェードアウト処理のマルチスレッド化：競合状態事前分析

**作成日**: 2026-05-04  
**対象**: `PlayerViewModel.startFadeOut()` と関連処理のスレッドセーフティ

---

## 1️⃣ 現在の実装構造

### 呼び出しスレッド図

```
handleTrackEnd()
  ├─ スレッド: DispatchQueue.global(qos: .userInitiated) [updateDisplay内から]
  │  ├─ status = .stopped (メインスレッド context へ dispatch)
  │  ├─ displayTimer?.invalidate()
  │  └─ startFadeOut() を呼び出し
  │
  └─ startFadeOut()
     ├─ スレッド: 同上（バックグラウンド）か メインスレッド？
     │  【問題】: DispatchQueue.main.async で UI更新後に呼ばれるため、実装によっては混在の可能性
     │
     ├─ fadeOutVolume = 1.0 [直接書き込み]
     │
     └─ Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true)
        ├─ タイマーコールバック [実行スレッド不定：Timer の RunLoop に依存]
        │
        ├─ self.fadeOutVolume -= 1.0 / Float(fadeOutSteps) [読み書き競合]
        ├─ self.audioService.setVolume(...) [AVAudioEngine のメインスレッド要件]
        ├─ print(...) ログ出力
        ├─ if fadeOutVolume <= 0.0 チェック [データ競合]
        │
        ├─ timer.invalidate() [タイマーライフサイクル]
        ├─ self.fadeOutTimer = nil [メモリ管理]
        ├─ self.fadeOutVolume = 1.0 [復帰]
        ├─ self.audioService.setVolume(1.0)
        │
        └─ self.playNextTrack()
           └─ DispatchQueue.main.async [メインスレッドへ dispatch]
```

---

## 2️⃣ 識別された競合状態（Race Conditions）

### 🔴 A. fadeOutVolume の データ競合

**現象**: `fadeOutVolume` は複数スレッドから同時にアクセスされる

| スレッド | 操作 | タイミング |
|---------|------|-----------|
| Timer RunLoop | 読み取り `self.fadeOutVolume -= ...` | 毎 50ms |
| Timer RunLoop | 比較 `if self.fadeOutVolume <= 0.0` | 毎 50ms |
| メインスレッド | 読み取り（表示更新）？ | 不定 |
| バックグラウンド | 初期化 `fadeOutVolume = 1.0` | startFadeOut() 開始時 |

**データレース詳細**:
```swift
// Timer RunLoop スレッド (例: thread-2)
self.fadeOutVolume -= 1.0 / Float(fadeOutSteps)  // ✗ READ-MODIFY-WRITE

// メインスレッド (例: thread-1) が同時実行
self.fadeOutVolume // 読み取り（UI更新で使用される可能性）
```

**問題1a: 不可分操作の欠落**
- `fadeOutVolume -= x` は内部的には `fadeOutVolume = fadeOutVolume - x` の3ステップ
- タイマーが複数回呼ばれた場合、更新が欠落する可能性あり

**問題1b: メモリの可視性**
- Thread 1 が `fadeOutVolume` を更新しても、Thread 2 がその値をすぐに読み取るか保証されない（キャッシュコヒーレンシー）
- Swift の `@Observable` マクロはメインスレッドを想定しており、バックグラウンド書き込みは非推奨

---

### 🔴 B. fadeOutTimer のライフサイクル競合

**現象**: `fadeOutTimer` の作成・無効化・nil化が競合する

| スレッド | 操作 | タイミング |
|---------|------|-----------|
| バックグラウンド | `fadeOutTimer = Timer.scheduledTimer(...)` | startFadeOut() |
| メインスレッド | UI 破棄時 `fadeOutTimer?.invalidate()` | deinit / cleanup |
| Timer RunLoop | `timer.invalidate()` | fadeOutVolume <= 0 時 |
| Timer RunLoop | `self.fadeOutTimer = nil` | 完了時 |

**問題2a: 二重 invalidate**
```swift
// メインスレッド
fadeOutTimer?.invalidate()  // 無効化

// タイマーコールバック (別スレッド)
timer.invalidate()  // 既に無効化済みで安全？要確認
```

**問題2b: ゾンビ参照（Use-After-Free）**
- `fadeOutTimer = nil` した直後に、別スレッドが `fadeOutTimer?.invalidate()` にアクセス
- オブジェクトが既に解放されている可能性

---

### 🔴 C. audioService.setVolume() の スレッド要件違反

**現象**: AVAudioEngine は**メインスレッドのみ**で操作すべき

```swift
// Timer RunLoop スレッド（例: thread-2）
self.audioService.setVolume(max(0.0, self.fadeOutVolume))
```

**実装内容** (MXDRVAudioEngine.swift):
```swift
func setVolume(_ volume: Float) {
    engine.mainMixerNode.outputVolume = max(0.0, min(volume, 1.0))
    // AVAudioEngine のノード操作はメインスレッド必須
}
```

**問題3: AVAudioEngine のスレッド安全性違反**
- AVAudioEngine のノード操作はメインスレッドでのみ安全
- Timer が RunLoop の任意のスレッドで実行された場合、`outputVolume` 書き込みがデータレースになる可能性

**実装での回避可能性**:
- `AVAudioEngine` は内部でロック機構を持つため、直接のクラッシュは稀
- ただし、音量変更の遅延や不一致が発生する可能性

---

### 🔴 D. playNextTrack() への DispatchQueue.main.async 二重化

**現象**: 既にメインスレッド内から `playNextTrack()` を呼んでいるのに、内部で再度 `DispatchQueue.main.async` を実行

```swift
// Timer RunLoop スレッド
self.playNextTrack()  // コールスタック

// playNextTrack() の内部
DispatchQueue.main.async { [weak self] in
    // メインスレッド処理
}
```

**問題4a: Deadlock 可能性**
- Timer が RunLoop の mainThread で実行された場合、`DispatchQueue.main.async` で自分自身を待つことになり、デッドロック可能性

**問題4b: 過度なコンテキストスイッチ**
- バックグラウンドスレッド → メインスレッド → バックグラウンド... の連鎖で CPU オーバーヘッド増加

---

### 🟡 E. status の 状態遷移競合（軽度）

**現象**: `status` は `@Observable` で管理されており、メインスレッド外での更新は非推奨

```swift
// updateDisplay (DispatchQueue.global)
DispatchQueue.main.async {
    self.currentTimeMs = ms  // メインスレッド更新（OK）
    self.spectrumBars = newBars  // OK
}

// handleTrackEnd (DispatchQueue.global)
status = .stopped  // ❌ メインスレッド外での @Observable 更新
```

**問題5: @Observable マクロの前提違反**
- `@Observable` は `@MainActor` の補足機能として扱われることが多い
- `@Observable` マクロ付きプロパティの変更は、アプリが特定のスレッドの変更を検出できない可能性

---

## 3️⃣ 潜在的な症状（実装バグの兆候）

| 現象 | 原因 | 重症度 |
|------|------|--------|
| 音量が途中で止まる | fadeOutVolume の更新欠落 | 🔴 高 |
| アプリクラッシュ（EXC_BAD_ACCESS） | ゾンビ参照（fadeOutTimer） | 🔴 高 |
| 音量がちらつく | setVolume のスレッド競合 | 🟡 中 |
| 次の曲が再生されない | playNextTrack のデッドロック | 🔴 高 |
| UI 更新漏れ | status 変更の可視性不足 | 🟡 中 |

---

## 4️⃣ 現在の実装が回避できている理由

**運が良い条件**:
1. **Timer の Main RunLoop 実行**: Timer がメインスレッドで実行される場合が多く、競合が少ない
2. **AVAudioEngine の内部ロック**: 多くの場合、内部でロック機構を持つため直接のクラッシュは回避
3. **テスト期間が短い**: フェードアウトは 3秒の短い処理のため、競合タイミングが低確率
4. **観察対象者がいない**: 競合が発生しても、UI に直接的な影響が見えにくい（音量変化なので主観的）

---

## 5️⃣ マルチスレッド化の戦略選択肢

### 戦略 A: タイマーをメインスレッド固定

**方針**: Timer を明示的にメインスレッド RunLoop に登録

```swift
func startFadeOut() {
    fadeOutVolume = 1.0
    let fadeOutDuration = 3.0
    let fadeOutInterval = 0.05
    let fadeOutSteps = Int(fadeOutDuration / fadeOutInterval)

    // メインスレッド RunLoop に登録（コンテキストスイッチなし）
    fadeOutTimer = Timer(timeInterval: fadeOutInterval, repeats: true) { [weak self] _ in
        // コールバックはメインスレッド実行保証
        self?.updateFadeOutVolume(steps: fadeOutSteps)
    }
    RunLoop.main.add(fadeOutTimer!, forMode: .common)
}
```

**利点**:
- ✅ fadeOutVolume の競合ゼロ（メインスレッドのみアクセス）
- ✅ AVAudioEngine.setVolume のスレッド要件満たし
- ✅ playNextTrack の二重化を避けられる
- ✅ @Observable との親和性高い

**欠点**:
- ❌ メインスレッドを 3秒間ブロック（フレームレート低下の可能性）
- ❌ UI 応答性が悪化

---

### 戦略 B: Atomic + DispatchQueue での同期化

**方針**: `fadeOutVolume` を atomic 変数化し、DispatchQueue で直列化

```swift
private var fadeOutVolume: AtomicFloat = AtomicFloat(1.0)  // atomic property

func startFadeOut() {
    let syncQueue = DispatchQueue(label: "fadeout.sync")
    
    fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
        syncQueue.async { [weak self] in
            self?.fadeOutVolume.value -= ...
            DispatchQueue.main.async {
                self?.audioService.setVolume(...)
            }
        }
    }
}
```

**利点**:
- ✅ DispatchQueue での直列化で明示的な同期化
- ✅ メインスレッドをブロックしない
- ✅ fadeOutVolume の不可分性を保証

**欠点**:
- ❌ DispatchQueue のコンテキストスイッチオーバーヘッド（毎 50ms）
- ❌ Atomic 実装が必要（Swift 標準には AtomicFloat がない）
- ❌ playNextTrack が二重化される（内部で再び DispatchQueue.main.async）

---

### 戦略 C: AsyncSequence + Task での非同期シーケンス化（推奨候補）

**方針**: Timer の代わりに AsyncSequence を使用

```swift
private var fadeOutTask: Task<Void, Never>?

func startFadeOut() {
    fadeOutTask = Task {
        let fadeOutDuration = 3.0
        let fadeOutInterval = 0.05
        let fadeOutSteps = Int(fadeOutDuration / fadeOutInterval)
        let decrement = 1.0 / Float(fadeOutSteps)
        
        for step in 0..<fadeOutSteps {
            try? await Task.sleep(nanoseconds: UInt64(fadeOutInterval * 1_000_000_000))
            
            await MainActor.run {
                fadeOutVolume -= decrement
                audioService.setVolume(max(0, fadeOutVolume))
            }
        }
        
        await MainActor.run {
            fadeOutVolume = 1.0
            audioService.setVolume(1.0)
            playNextTrack()
        }
    }
}
```

**利点**:
- ✅ `@MainActor.run` で明示的にメインスレッド実行
- ✅ fadeOutVolume の競合完全排除
- ✅ AVAudioEngine のスレッド要件満たし
- ✅ playNextTrack を直接呼び出し（二重化なし）
- ✅ キャンセル機構が簡潔（Task.cancel()）

**欠点**:
- ❌ Task.sleep のコストが Timer より若干高い（ただしマイクロ秒レベル）
- ❌ iOS 13 未満には非対応（既に対応外）

---

### 戦略 D: os_unfair_lock + os_signpost での Manual 同期化

**方針**: MXDRVG エンジンで既に実装されている `os_unfair_lock` を再利用

```swift
private var fadeOutVolume: Float = 1.0
private var fadeOutLock = os_unfair_lock()

func startFadeOut() {
    let syncQueue = DispatchQueue(label: "fadeout.sync")
    
    fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            os_unfair_lock_lock(&self.fadeOutLock)
            defer { os_unfair_lock_unlock(&self.fadeOutLock) }
            
            self.fadeOutVolume -= ...
            
            DispatchQueue.main.async {
                self.audioService.setVolume(...)
            }
        }
    }
}
```

**利点**:
- ✅ os_unfair_lock は軽量（プリエンプション対応）
- ✅ 既存コードベースとの一貫性（MXDRVG で既出）
- ✅ 低オーバーヘッド

**欠点**:
- ❌ 手動ロック管理で複雑度増加
- ❌ コンテキストスイッチのコスト（DispatchQueue + os_unfair_lock）
- ❌ playNextTrack の二重化問題あり

---

## 6️⃣ 推奨される実装戦略

### **推奨: 戦略 C (AsyncSequence + @MainActor.run)**

**理由**:
1. **最も安全**: @MainActor で完全にメインスレッド化
2. **最も明確**: スレッド意図が一目瞭然（コード可読性が高い）
3. **既存パターンに準拠**: MP4M の updateDisplay ですでに Task.detached が使われており、async/await パターンが確立されている
4. **最小オーバーヘッド**: コンテキストスイッチが効率的
5. **キャンセル対応**: Task.cancel() で簡潔にクリーンアップ可能

### **次点: 戦略 A (メインスレッド RunLoop 固定)**

**使用場面**:
- 最小限の変更を望む場合
- Timer のメインスレッド実行が既に保証されている場合

**懸念**: メインスレッドの 3秒ブロックが UI フレームレートに影響する可能性（実測が必要）

---

## 7️⃣ 実装前チェックリスト

マルチスレッド化を実装する前に、以下を確認する：

- [ ] Task.sleep() の精度が 50ms ステップで十分か（50ms は人間が知覚できる限界）
- [ ] fadeOutVolume を UI に表示する必要はないか（表示しない場合、@Observable の要件が下がる）
- [ ] cancel 処理時の cleanup（fadeOutTask?.cancel()）で fadeOutVolume 復帰が必要か
- [ ] playNextTrack() のメイン処理内に DispatchQueue.main.async が必要か（既に MainActor コンテキストなら削除可能）
- [ ] スレッド Sanitizer で実装検証できるか（UI テスト環境）

---

## 8️⃣ 次のステップ

1. **詳細な実装設計**: 選定戦略に基づき、変更対象ファイル・メソッドシグネチャを確定
2. **Deadlock シミュレーション**: 特に playNextTrack の入れ子化による deadlock リスク評価
3. **パフォーマンステスト**: メインスレッド実行時の UI フレームレート測定
4. **Thread Sanitizer 検証**: 本番環境で Thread Sanitizer を有効化して実装検証

---

