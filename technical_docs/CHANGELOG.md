# Changelog

All notable changes to MP4M (macOS MDX Player) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- iOS/iPad support (separate UI branch)
- Full keyboard shortcut implementation (Space, Arrow keys)
- Playlist management
- ZMUSIC (ZMD/ZDF) format support
- MDX/PDX metadata viewer

## [2.6.0] — 2026-06-03

### Changed
- **バージョン**: 2.5.0 → 2.6.0
- ビルド番号: 11 → 12

### Added
- **FileSelector の PATH 文字列を選択可能に (CR-001)**: Text に `.textSelection(.enabled)` を追加しドラッグ選択を許可。`.help()` でフルパスのツールチップ表示、右クリックメニューから `NSPasteboard` 経由で Copy できる動線を提供 (View のみの変更、Model / ViewModel には影響なし)

### Fixed
- **KNA03.MDX の中～高音打撃を ymfm で聞こえるように (CR-002)**: 対象曲: Arsys「Knight Arms」KNA03.MDX。ymfm 使用時のみ CH3 相当 (AR=31) の音が出ない症状を修正。`fm_operator::keyonoff()` で KeyOn 直前に `cache_operator_data()` を明示呼出してから `start_attack()` を呼ぶことで、`m_cache.eg_rate[EG_ATTACK]` を最新化。AR=31 (rate=62/63) で `start_attack()` 内の `>= 62` ジャンプ条件を満たすようにする。同時に ymfm オリジナルの `if (rate < 62)` 仕様 (= 攻撃 increment スキップ) を尊重し KNA シリーズ 25 曲で副次的な A1023 状態を表示しつつ実音は正常再生。詳細: `docs/ChangeRequest.md` CR-002 エントリ、`evidence/cr-002-resolution.md`

## [2.1.0] — 2026-05-30

### Fixed
- **ymfm 初回再生音色不良**: アプリ起動直後の初めての曲再生時のみ発生する音色データ適用失敗を、ymfm 内部エンベロープジェネレータへの直接リセット（`force_full_release`）により根本改善。MeasurePlayTime() 後のエンベロープ状態汚染が原因だった。
- 初回再生時と2回目以降の音色差異を大幅に縮小

### Changed
- **バージョン**: 2.0.0 → 2.1.0
- 単数形開発者表記に統一（"We do not" → "I do not" in About popup）

### Technical Details
- `OpmWrapper::ForceReleaseAllChannels()` を強化し、`fm_operator::force_full_release()` で `m_env_state = EG_RELEASE` + `m_env_attenuation = 0x3ff` を直接設定
- 呼び出しタイミング: `resetMXDRVGEngine()` および `playWithLoopCount()` の SetData 直後（ymfm エンジン使用時のみ）

## [1.0.0] — 2026-05-10

### Added
- **コマンドライン引数サポート**: バイナリ直接実行時にフルパスのディレクトリまたはMDXファイルを引数として受け取り、ルートディレクトリ設定・自動再生が可能に
- **シングルインスタンス制御**: `flock` によるロックファイルで多重起動を検出。既存インスタンスが存在する場合は `CFNotificationCenter`（DistributedNotification）でファイルパスを転送し、新規プロセスは即座に終了
- **IPCファイル開封**: 既存インスタンスが起動中の場合、別プロセスからのファイル開封要求を受け取り、ウィンドウを前面に表示して再生開始
- **`playAsync()`**: `MXDRVG_MeasurePlayTime`（曲の総再生時間計測）を `Task.detached` でバックグラウンド実行し、メインスレッドのブロックを防止

### Fixed
- **CLI起動時のフリーズ**: `playWithLoopCount` → `MXDRVG_MeasurePlayTime` がメインスレッドをブロックしていた問題を修正
- **CLI引数がUserDefaultsより優先されない問題**: `FileBrowserViewModel` の init が `CommandLine.arguments` を直接読むよう変更、SwiftUIの初期化タイミングに依存しない設計に
- **他プロセスからの起動でウィンドウが前面に出ない問題**: `NSApp.activate(ignoringOtherApps: true)` を `onAppear` に追加
- **DistributedNotificationの配送問題**: SwiftのFoundation overlayが `deliverImmediately` を公開していないため、`CFNotificationCenterPostNotification`（C API）で即時配送を実現
- **`pendingPath` の非同期設定タイミング問題**: `Task { @MainActor in ... }` から同期的な直接代入に変更し、ViewModel生成時に確実に値が反映されるよう修正
- **`playAsync()` の弱参照問題**: `Task.detached` のキャプチャを `[weak self]` から `[self]`（強参照）に変更し、再生開始前にViewModelが解放されるのを防止

### Changed
- **バージョン更新**: v0.9.1β → v1.0.0
- **Info.plist**: `CFBundleShortVersionString` を v1.0.0 に更新

### Technical Details
- **単一インスタンス方式**: `/tmp/com.ktam.MP4M.lock` を `flock(LOCK_EX | LOCK_NB)` でロック。クラッシュ時はカーネルが自動解放
- **IPC方式**: `CFNotificationCenterGetDistributedCenter()` + `CFNotificationCenterPostNotification(…, true)` で即時配送
- **引数パース**: `CommandLine.arguments[1]` → `(path as NSString).expandingTildeInPath` で `~` 展開対応

## [1.0] — 2026-05-03

### Initial Release

macOS MDX Player for X68000 music files with full multithreading support.

#### Added
- **Core Playback**: MDX/PDX file support, LZX decompression, 0-8 loop cycles, fade-out
- **Visualization**: 32-bar spectrum analyzer, 16-channel level meter, piano keyboard, track info
- **Playback Control**: Play/Pause/Stop, Next/Previous, Auto mode, Shuffle, Repeat, Per-channel mute
- **File Management**: Folder browser, automatic PDX discovery, Shift-JIS/UTF-8 title extraction
- **Audio Engine**: AVAudioEngine real-time rendering, 44.1kHz stereo, fmgen YM2151 emulation
- **Multi-threading**: os_unfair_lock + Task.detached for safe concurrent access, Apple Silicon optimization
- **UI Design**: SwiftUI + MVVM, X68000-inspired aesthetic
- **Security**: macOS App Sandbox, buffer validation, overflow protection

#### Performance
- CPU: 0-3.7% idle, 5-8% playback (Apple Silicon)
- Memory: 1.2% stable
- UI: 60fps target frame rate maintained

---

## Previous Development (2026-04-30 — 2026-05-02)

### Phase 1: Multithreading Optimization (Completed)

**Implementation:**
- os_unfair_lock added to MXDRVAudioEngine for concurrent C++ access
- Task.detached refactor for updateDisplay() to leverage Performance cores
- computeSpectrum() separation for pure function computation
- @MainActor batching for UI updates

**Verification:**
- ✅ Thread Sanitizer: 0 data race conditions
- ✅ CPU profiling: improved idle/playback metrics
- ✅ Manual testing: MDX playback stable, UI responsive

### Core Engine Stabilization

**Fixed Issues:**
- OPMINTFUNC double-invocation in GetPCM loop (playback speed 3-4x bug)
- TotalVolume initialization to 256 (silent audio issue)
- Sequence reset with L_0F() after MXDRVG_SetData
- Automatic PDX discovery in loadMDXFile

### YM2151 Implementation

**Register Mapping (Complete):**
- 0x40-0x5F: DT1/MUL, 0x60-0x7F: TL, 0x80-0x9F: KS/AR
- 0xA0-0xBF: AMS/D1R, 0xC0-0xDF: DT2/D2R, 0xE0-0xFF: D1L/RR
- Correct KeyOn, Timer A/B, Algorithm routing

### PCM/Channel Management

**Extended Support:**
- 16-channel state management (FM 1-8, PCM 9-16)
- Per-channel pan display (L/C/R/S)
- Level meter with dB scaling
- Channel mute with output level control

### MVVM Architecture

**Structure:**
- PlayerViewModel: State + UI logic
- FileBrowserViewModel: File browsing
- AudioEngineService: Protocol-based audio control
- MXDRVAudioEngine: AVAudioEngine implementation

---

## Known Limitations

- ZMUSIC (ZMD/ZDF) not supported
- macOS only (iOS support planned)
- Requires macOS 14.0+ (Sonoma)
- App Sandbox file access restrictions
- PDX must be in same directory as MDX

---

## Dependencies & Licenses

| Component | License | Commercial |
|-----------|---------|-----------|
| fmgen | cisc Copyright (Free distribution) | Requires prior agreement |
| MXDRVG | Apache 2.0 | Permitted |
| pcm8/x68pcm8 | Apache 2.0 | Permitted |
| LZX Decompression | 0BSD | Permitted |

See LICENSE file for complete texts.

---

**Last Updated**: 2026-05-03  
**Maintainer**: ktam  
**Repository**: https://github.com/ktam72/MP4M
