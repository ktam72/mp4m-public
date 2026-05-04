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
