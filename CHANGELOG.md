# MP4M — 修正履歴

## 2026-04-30 再生速度修正 + MVVMリファクタリング

### 問題1: 再生速度が異常に早い（約10倍速）

**原因**: `MXDRVG_GetPCM` (mxdrvg_core.h) でタイマー未設定時(`event_us == 0`)に `OPMINT_FUNC()` を2回呼んでいた。
- line 365: `event_us == 0` ブロック内で `OPMINT_FUNC()`
- line 385: PCM生成前にもう一度 `OPMINT_FUNC()`

`OPMINT_FUNC` は本来 256μsec 間隔のタイマー割り込みで呼ばれるもので、二重呼び出しによりシーケンス処理が過剰に進んでいた。

**修正**: `mxdrvg_core.h:MXDRVG_GetPCM` — `event_us == 0` ブロック内の `OPMINT_FUNC` 呼び出しを削除。PCM生成前の1回のみにする。

その後、冒頭再生されない問題が発覚したため、`event_us == 0` の時に `OPMINT_FUNC` を1回呼んでシーケンスを進める処理を復活（ただし1回のみ）。

```
event_us == 0 の場合:
  → OPMINT_FUNC() を1回呼ぶ
  → 再度 GetNextEvent() を確認
  → まだ 0 なら create_len = 1
  → イベントがあれば create_len を計算
タイマー設定済みの場合:
  → OPMINT_FUNC() は呼ばない (Count() → Intr → 自動呼び出しに委ねる)
```

---

### 問題2: `TotalVolume` の初期値が 0 で無音

**原因**: `mxdrvg_core.h` の `static int TotalVolume` が未初期化（デフォルト 0）。`MXDRVG_GetPCM` 内で `TotalVolume != 256` の場合に `sample * (TotalVolume >> 8)` = `sample * 0` で全サンプルがゼロに。

**修正**: `mxdrvg_core.h:MXDRVG_Start` で `TotalVolume = 256` を明示的に設定。

---

### 問題3: 再生開始冒頭2秒が再生されない

**原因**: `MXDRVG_SetData` で `OPMINT_FUNC()` を200回呼びOPMレジスタを初期化する際、各呼び出しで `G.PLAYTIME` が更新され、シーケンス位置も進んでしまう。その後 `playWithLoopCount` で `MXDRVG_SetData` を再実行すると、進んだ状態から始まっていた。

**修正**: `mxdrvg_core.h:MXDRVG_SetData` の `OPMINT_FUNC` ループ後に `L_0F()` を再度呼び、シーケンス位置と再生時間を冒頭へリセットする。OPMレジスタ状態は保持される。

---

### 問題4: EXC_BREAKPOINT (リアルタイムオーディオスレッド)

**原因**: `AVAudioSourceNode` のレンダーコールバック内で `[Int16](repeating:count:)` によるメモリ確保が発生していた。リアルタイムオーディオスレッドでの `malloc` は EXC_BREAKPOINT を引き起こす。

**修正**: `pcmBuffer` を最大サイズ (2048要素) で事前確保。レンダーコールバックでは事前確保済みバッファのみを使用。

---

### 問題5: `_dispatch_assert_queue_fail` (MainActor隔離違反)

**原因**: `MDXPlayer` クラス全体に `@MainActor` 属性が付いていたが、`AVAudioSourceNode` のコールバックはオーディオIOスレッドから実行されるため、MainActor隔離されたメソッドへのアクセスで失敗。

**修正**: `MDXPlayer` からクラスレベルの `@MainActor` を削除、`@unchecked Sendable` を追加。UI-facing メソッドにのみ `@MainActor` を付与。

---

## MVVM リファクタリング

### 構成変更

**削除:**
- `MP4M/Audio/MDXPlayer.swift` → Service + ViewModel に分散
- `MP4M/Models/PlaybackState.swift` → ViewModel に統合

**追加:**
- `MP4M/Models/AudioModels.swift` — ドメインモデル (PlayStatus, AutoMode, ChannelDisplayState, SpectrumBarState)
- `MP4M/Services/AudioEngineService.swift` — オーディオエンジンプロトコル (テスト用モック化可能)
- `MP4M/Services/MXDRVAudioEngine.swift` — AVAudioEngine + MXDRVGBridge の実装
- `MP4M/ViewModels/PlayerViewModel.swift` — 再生状態管理 + スペアナ計算 + 曲送りロジック
- `MP4M/ViewModels/FileBrowserViewModel.swift` — ファイルブラウザ状態管理

**更新:**
- `MP4M/Views/ContentView.swift` — ViewModel 生成・委譲
- `MP4M/Views/TrackInfoView.swift` — PlayerViewModel バインド
- `MP4M/Views/SpectrumAnalyzerView.swift` — PlayerViewModel バインド
- `MP4M/Views/LevelMeterView.swift` — PlayerViewModel バインド
- `MP4M/Views/KeyboardView.swift` — PlayerViewModel バインド
- `MP4M/Views/FileSelectorView.swift` — FileBrowserViewModel バインド
- `MP4M/Views/ControlPanelView.swift` — ViewModel バインド

### データフロー (変更後)

```
View (SwiftUI)
    │ @Bindable / let 経由で ViewModel を参照
    ▼
ViewModel (@Observable)
    │ AudioEngineService プロトコル経由で操作
    ▼
Service (プロトコル)
    │ MXDRVAudioEngine が実装
    ▼
MXDRVGBridge (ObjC++)
    │
    ▼
MXDRVG C++ エンジン (Vendor/gamdx)
```

### 設計上の利点

1. **テスト容易性**: `AudioEngineService` はプロトコルなのでモックに差し替え可能
2. **関心分離**: View は表示のみ、ViewModel が状態・ロジックを管理、Service がオーディオ処理を担当
3. **依存方向**: View → ViewModel → Service → Bridge の一方向依存
4. **スレッド分離**: オーディオスレッド処理は Service 内に閉じ込め、ViewModel は @MainActor で動作
