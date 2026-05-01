# MP4M — 設計ドキュメント

SHARP X68000 用音楽プレーヤー「MP4M」の macOS SwiftUI 移植版。
MDX/PDX 形式の音楽ファイルをリアルタイム再生し、スペクトラムアナライザー・レベルメーター・キーボード表示を持つ。

---

## 技術スタック

| 要素 | 採用技術 | 備考 |
|---|---|---|
| プラットフォーム | macOS 14.0+ | Sonoma 以降 |
| UI | SwiftUI + Swift 6.0 | `@Observable` マクロ使用 |
| アーキテクチャ | MVVM | `PlayerViewModel` + `FileBrowserViewModel` |
| 音声出力 | AVAudioEngine + AVAudioSourceNode | リアルタイムレンダリング |
| MDX/PDX デコーダー | MXDRVG (C++) | ObjC++ ブリッジ経由 |
| OPM 合成エミュレーター | オリジナル実装 (C++) | YM2151 エミュレーション (商用利用可能 0BSD) |
| PCM/ADPCM | pcm8 / x68pcm8 (C++) | X68000 ADPCM 互換 |
| LZX 解凍 | オリジナル実装 (C++) | LZ77方式、商用利用可能 0BSD |
| フォント | KH-Dot-Kodenmachou-16 | X68000 風ドットフォント |
| プロジェクト管理 | xcodegen + project.yml | `xcodegen generate` で再生成 |

---

## サポートフォーマット

- **MDX** — MXDRV 形式 (X68000 OPM FM 音源)
- **PDX** — ADPCM サンプルデータ (MDX と同ディレクトリに配置で自動ロード)
- ZMD / ZDF — 非サポート (ZMUSIC 形式はデコーダー不在のため除外)

---

## アーキテクチャ (MVVM)

```
MP4MApp
└── ContentView
    ├── TrackInfoView        タイトル・経過時間・総時間・ドライバー名
    ├── SpectrumAnalyzerView 32バー スペアナ (ピーク保持付き)
    ├── LevelMeterView       16ch FM レベルメーター (パン表示付き)
    ├── KeyboardView         8ch ピアノキーボード (発音ハイライト)
    ├── FileSelectorView     MDX ファイルブラウザ
    └── ControlPanelView     再生操作・ループ・オートモード
         │
         ▼
    PlayerViewModel (@Observable, @MainActor)
    ├── status: PlayStatus
    ├── channels: [ChannelDisplayState] (16ch)
    ├── spectrumBars: [SpectrumBarState] (32ch)
    └── audioService: AudioEngineService (プロトコル)
         │
         ▼
    MXDRVAudioEngine : AudioEngineService
    ├── AVAudioEngine + AVAudioSourceNode
    ├── レンダーコールバック → MXDRVG_GetPCM
    └── スレッドセーフなチャンネル状態取得
```

### データフロー

```
MDX ファイル
    │
    ▼
MXDRVGBridge.mm (ObjC++)
     ├── lzx で LZX 解凍（オリジナル実装）（オリジナル実装）
    ├── MDX ヘッダー解析 + Shift-JIS タイトル抽出
    ├── MXDRVG_SetData でエンジンに渡す
    └── MXDRVG_PlayAt で再生開始
         │
         ▼
MXDRVAudioEngine (AVAudioSourceNode レンダーコールバック)
    ├── MXDRVG_GetPCM → int16 インターリーブ → float 非インターリーブ変換
    ├── AVAudioEngine → スピーカー出力
    └── Timer (60fps) → PlayerViewModel.updateDisplay()
         │
         ▼
PlayerViewModel (@Observable, @MainActor)
    ├── channels[16]: ChannelDisplayState (keyCode, velocity, keyOn, volume, bend, pan)
    ├── spectrumBars[32]: SpectrumBarState (current, peak, peakTimer)
    └── 擬似スペアナ計算 (キーコード→周波数ビンマッピング)
         │
         ▼
SwiftUI Views (リアルタイム描画)
```

---

## ディレクトリ構成

```
MP4M/
├── project.yml                     xcodegen 定義
├── MP4M.xcodeproj                 (xcodegen 生成、手動編集禁止)
├── MP4M/
│   ├── App/
│   │   └── MP4MApp.swift          エントリーポイント + フォント登録
│   ├── Bridge/
│   │   ├── MP4M-Bridging-Header.h Swift ブリッジヘッダー
│   │   ├── MXDRVGBridge.h          ObjC インターフェース宣言
│   │   └── MXDRVGBridge.mm         ObjC++ 実装 (C++ エンジン呼び出し)
│   ├── ViewModels/
│   │   ├── PlayerViewModel.swift   再生状態・スペアナ計算 (@Observable, @MainActor)
│   │   └── FileBrowserViewModel.swift ファイルブラウザ用 ViewModel
│   ├── Services/
│   │   ├── AudioEngineService.swift  オーディオエンジンプロトコル
│   │   └── MXDRVAudioEngine.swift   AVAudioEngine 実装
│   ├── Models/
│   │   ├── AudioModels.swift        ChannelDisplayState, SpectrumBarState 等
│   │   └── FileItem.swift          ファイルブラウザ用モデル
│   ├── Views/
│   │   ├── Theme.swift             カラー・フォント定数
│   │   ├── ContentView.swift       メインレイアウト
│   │   ├── SpectrumAnalyzerView.swift
│   │   ├── LevelMeterView.swift    16ch対応、パン表示(L/C/R)
│   │   ├── KeyboardView.swift
│   │   ├── TrackInfoView.swift
│   │   ├── FileSelectorView.swift
│   │   └── ControlPanelView.swift
│   └── Resources/
│       ├── Assets.xcassets
│       ├── KH-Dot-Kodenmachou-16-Ki.ttf
│       ├── s2utbl.dat              Shift-JIS → UTF-8 変換テーブル
│       └── MP4M.entitlements
└── Vendor/
    ├── gamdx/jni/                  MDXPlayer-main から流用した C++ エンジン
    │   ├── mxdrvg/  so.cpp, mxdrvg.h, mxdrvg_core.h, mxdrvg_depend.h
    │   ├── pcm8/    pcm8.cpp, x68pcm8.cpp
    │   └── downsample/ downsample.cpp
    ├── opm/                          オリジナルOPMドライバ (商用利用可能 0BSD)
    │   ├── opm.h         API ヘッダー
    │   ├── opm_device.cpp  メイン実装
    │   ├── operator.h/cpp   FM オペレーター実装
    │   ├── channel.h/cpp   4-op チャンネル実装
    │   ├── lfo.h/cpp        LFO 実装
    │   ├── timer.h/cpp     タイマー実装
    │   └── opm_wrapper.h/cpp MXDRVG 連携用ラッパー
    └── lzx/                          オリジナルLZX解凍 (商用利用可能 0BSD)
        ├── lzx.h         API ヘッダー
        └── lzx.cpp       LZ77方式解凍実装
```

> `MP4M.xcodeproj` を直接編集した場合は `xcodegen generate` で上書きされる。
> ソース追加・設定変更は必ず `project.yml` を編集してから `xcodegen generate` で再生成する。

---

## MXDRVG エンジン API (主要)

| 関数 | 用途 |
|---|---|
| `MXDRVG_Start(rate, fast, mdxbuf, pdxbuf)` | エンジン初期化 |
| `MXDRVG_End()` | エンジン終了・メモリ解放 |
| `MXDRVG_SetData(mdx, mdxsize, pdx, pdxsize)` | MDX/PDX データ設定 (10byte プリヘッダー必須) |
| `MXDRVG_MeasurePlayTime(loop, fadeout)` | 総再生時間計測 (PlayAt 前に呼ぶ) |
| `MXDRVG_PlayAt(pos, loop, fadeout)` | 指定位置から再生開始 |
| `MXDRVG_GetPCM(buf, len)` | PCM レンダリング (int16 インターリード stereo) |
| `MXDRVG_GetWork(MXDRVG_WORKADR_FM)` | FM チャンネル状態ポインタ取得 |
| `MXDRVG_GetWork(MXDRVG_WORKADR_GLOBAL)` | グローバル状態ポインタ取得 |
| `MXDRVG_GetPlayAt()` | 現在再生位置 (ミリ秒) |
| `MXDRVG_GetTerminated()` | 演奏終了フラグ |
| `MXDRVG_Stop/Pause/Cont()` | 停止・一時停止・再開 |

**注意**: `MXDRVG_SetData` に渡す MDX/PDX バッファには先頭 10 バイトのプリヘッダーが必要。
詳細は `MXDRVGBridge.mm` の `wrapMDX()` / `wrapPDX()` を参照。

**既知の修正**:
- `MXDRVG_MeasurePlayTime` は内部状態を曲終端まで進めるため、その後再生する場合は再初期化が必要
- `MXDRVG_GetPCM` 内で `OPMINTFUNC` を二重に呼んでいた不具合を修正（再生速度が異常に早くなる問題）
- `TotalVolume` の初期値を256に設定（無音問題の修正）
- `MXDRVG_SetData` 後に `L_0F()` を再呼び出ししてシーケンス位置をリセット（冒頭再生欠落の修正）
- fmgen/ymfm を完全に廃止し、YM2151データシートからオリジナルOPMドライバを全新規実装（0BSDライセンス）
- LZX解凍もオリジナル実装（0BSD）に置き換え、すべてのVendorコードが商用利用可能に

---

## スペクトラムアナライザーのアルゴリズム

`PlayerViewModel.swift: updateSpectrum()` に実装。`SpeanaBitmap.m` (MDXPlayer-main) からの Swift 移植。

1. 各 FM チャンネルのキーコード・ベロシティを周波数ビン (52個) にマッピング
2. 周辺ビンへ拡散 (隣接ビンへ振幅の 3/4, 5/16, 1/8, 1/4, 1/16 を加算)
3. 擬似対数変換テーブル `routeTable` で 0〜28 段階に変換
4. 上昇時は `riseTable` で急峻に上昇、下降時は 2段/フレーム で緩やかに落下
5. ピーク保持: 10フレーム間最高値を保持してから 1段/フレーム で降下

---

## MDX ファイルフォーマット (解析部分)

```
[タイトル (Shift-JIS)] [CR LF]
[0x1A]
[PDX ファイル名 (Shift-JIS, ゼロ終端)] [0x00]
[MDX トラックデータ本体 (LZX 圧縮またはそのまま)]
```

- PDX ファイル名が空の場合は PDX なし
- LZX 圧縮判定: `lzx042check()` で正の値が返れば圧縮済み

---

## UI デザイン方針

- **カラー**: 黒背景 + 緑/シアン系 (X68000 CRT モニター風)
- **フォント**: KH-Dot-Kodenmachou-16 (ドットフォント、Shift-JIS 対応)
- **レイアウト**: 元の MP4M レイアウトを参考に SwiftUI で再構成
- **フォントフォールバック**: KH-Dot 未登録時も UI は機能する (SF Mono 代替)
- 色定数・フォント定数は `Theme.swift` に集約

---

## ビルド・開発手順

```bash
# プロジェクト再生成 (project.yml 変更後)
cd /Users/ktam/Documents/apps/MP4M
xcodegen generate

# CLI ビルド
xcodebuild -project MP4M.xcodeproj -scheme MP4M -configuration Debug build

# Xcode で開く
open MP4M.xcodeproj
```

---

## セキュリティ対策

| 対策 | 対象ファイル | 内容 |
|---|---|---|
| ファイルサイズ下限チェック | `MXDRVGBridge.mm` | MDX/PDX の最小サイズ検証 |
| ヘッダー境界チェック | `MXDRVGBridge.mm` | Shift-JISタイトル抽出時のバッファオーバーラン防止 |
| パストラバーサル防止 | `MXDRVGBridge.mm` | PDXファイル名のパス区切り文字チェック |
| LZX展開サイズ制限 | `lzx/lzx.cpp` | 展開後サイズの上限(1MB)設定 |
| LZXバッファオーバーフロー防止 | `lzx/lzx.cpp` | 展開先バッファの境界チェック |
| シーケンスポインタ範囲チェック | `mxdrvg_core.h` | 不正なシーケンスアドレスへのアクセス防止 |
| 再生ループ上限 | `mxdrvg_core.h` | 無限ループ防止（1000万回イテレーション上限） |

---

## 既知の制約・TODO

- **ZMD/ZDF 非サポート**: ZMUSIC デコーダー未実装のため対応外
- **ドキュメントビューア**: 元の MP4M にあった `.doc` 表示は未実装
- **キーボードショートカット**: スペースキー再生/一時停止など未実装
- **プログラムプレイ**: プレイリスト管理機能は未実装
- **レベルメーターのパン表示**: 3値(L/C/R)のみ表示。中間パン位置は `・` で表示
- **PCM8 チャンネル状態**: 16ch表示対応済み。PCM8ch (9-16) はワークエリアの制約によりキー状態のみ表示

---

## 修正履歴

### 2026-05-01 (4) — オリジナル実装完全移行・ライセンスクリア
- **オリジナルOPMドライバ実装**: fmgen/ymfmのコードを一切流用せず、YM2151データシートから全新設計・実装（0BSDライセンス、商用利用可能）
  - `Vendor/opm/` に配置：opm.h、operator.cpp/h、channel.cpp/h、lfo.cpp/h、timer.cpp/h、opm_wrapper.cpp/h
  - API設計：`opm.h` でクリーンなインターフェース、`OpmWrapper` でMXDRVGと互換
  - Operator、Channel(4-op)、LFO、Timer、ステレオ出力・パン表示、ノイズ生成を完備
- **LZX解凍オリジナル実装**: lzx042を廃止し、Microsoft LZX仕様に基づく全新規実装（0BSDライセンス）
  - `Vendor/lzx/` に配置：lzx.h、lzx.cpp（LZ77方式、Huffman/ビットリーダー）
  - `MXDRVGBridge.mm` を新しい `lzx::Check()` / `lzx::Decompress()` に更新
- **fmgen完全削除**: `project.yml` からfmgenを削除、すべてのC++エンジンをオリジナル実装に置換え
- **ライセンス完全クリア**: すべてのVendorコードが0BSDまたはApache 2.0で商用利用可能に
- **ビルド成功**: `xcodebuild` で BUILD SUCCEEDED を確認、アプリ起動済み

### 2026-05-01 (1) — fmgen再移行（その後廃止）
- **fmgen への再移行**: ymfm から fmgen にOPMエミュレーターを戻し、YM2151タイマー割り込み頻度を61Hzに修正、再生速度異常を解消
- **project.yml 修正**: fmgen/mxdrvg/pcm8/downsample をフォルダ単位のソース指定に変更、Xcodeでフォルダグループが表示されるように調整
- **mxdrvg_core.h 統合修正**: FOOpmWrapperの修正、`Intr()` の `override` 指定子削除など
- **ビルド成功**: `xcodebuild` で BUILD SUCCEEDED を確認、アプリ起動済み

### 2026-04-30
- **PCM8 16ch対応**: レベルメーター・チャンネル状態取得をFM8ch + PCM8chの16chに拡張
- **再生不具合修正**: `MXDRVG_GetPCM` 内の `OPMINTFUNC` 二重呼び出し修正、`TotalVolume` 初期値256設定、`L_0F()` によるシーケンスリセット
- **MVVMリファクタリング**: `MDXPlayer.swift` / `PlaybackState.swift` を `PlayerViewModel.swift` + `MXDRVAudioEngine.swift` に分割
- **セキュリティ強化**: ヘッダー解析・LZX展開・シーケンス処理に境界チェック追加
- **レベルメーター改善**: 8ch → 16ch対応、パン表示(L/C/R)追加、デフォルトレベル0修正
- **デバッグログ削除**: `mxdrvg_core.h` の無条件 `printf` 削除

### 2026-04-30 (ymfm導入 — その後廃止)
- **FM音源エンジン置き換え**: fmgen (cisc) → ymfm (Aaron Giles, BSD 3-Clause) に置き換え
- **YMFMOpmWrapper実装**: fmgen互換インターフェースを提供するラッパークラスを追加
- **割り込み処理変更**: fmgenのタイマーコールバック方式からymfmのステータスポーリング方式に変更
- **project.yml更新**: fmgenソースを削除、ymfmソースに置換え

### 2026-05-01 (1) — fmgen再移行（その後廃止）
- **fmgen への再移行**: ymfm から fmgen にOPMエミュレーターを戻し、YM2151タイマー割り込み頻度を61Hzに修正、再生速度異常を解消
- **project.yml 修正**: fmgen/mxdrvg/pcm8/downsample をフォルダ単位のソース指定に変更
- **mxdrvg_core.h 統合修正**: FOOpmWrapperの修正、`Intr()` の `override` 指定子削除など
- **ビルド成功**: BUILD SUCCEEDED を確認、アプリ起動済み

### 2026-04-30
- **PCM8 16ch対応**: レベルメーター・チャンネル状態取得をFM8ch + PCM8chの16chに拡張
- **再生不具合修正**: `OPMINTFUNC` 二重呼び出し修正、`TotalVolume` 初期値256設定、`L_0F()` シーケンスリセット
- **MVVMリファクタリング**: `MDXPlayer.swift` / `PlaybackState.swift` を `PlayerViewModel.swift` + `MXDRVAudioEngine.swift` に分割
- **セキュリティ強化**: ヘッダー解析・LZX展開・シーケンス処理に境界チェック追加
- **レベルメーター改善**: 8ch → 16ch対応、パン表示(L/C/R)追加
- **PCM8 パン表示対応**: PCM8ch (9-16) のパン情報をLEVELメーターに反映
- **LEVELメーター可変幅化**: 最大化時に16chが均等に間隔を広げて描画されるよう修正
- **デバッグログ削除**: `mxdrvg_core.h` の無条件 `printf` 削除

### 2026-04-30 (ymfm導入 — その後廃止)
- **FM音源エンジン置き換え**: fmgen → ymfm (BSD 3-Clause) に置き換え
- **YMFMOpmWrapper実装**: fmgen互換インターフェースを提供するラッパークラスを追加
- **割り込み処理変更**: fmgenのタイマーコールバック方式からymfmのステータスポーリング方式に変更

### 2026-05-01 (4)
- **LZX解凍オリジナル実装**: lzx042を廃止し、Microsoft LZX仕様に基づく全新規実装（0BSDライセンス）
- **実装内容**: `Vendor/lzx/` に配置、LZ77方式の圧縮解凍、Huffman/ビットリーダー実装
- **MXDRVGBridge修正**: `MXDRVGBridge.mm` を新しい `lzx::Check()` / `lzx::Decompress()` に更新
- **fmgen完全削除**: `project.yml` からfmgenを削除、すべてのC++エンジンをオリジナル実装に置換え
- **ライセンス完全クリア**: すべてのVendorコードが0BSDまたはApache 2.0で商用利用可能に

---

## 依存ライブラリ

| ライブラリ | ライセンス | 用途 |
|---|---|---|
| MXDRVG (gamdx) | Apache 2.0 (GORRY) | MDX デコード・シーケンス処理 |
| オリジナルOPMドライバ | 0BSD (商用利用可能) | YM2151 FM 音源エミュレーション (全新規実装) |
| オリジナルLZX解凍 | 0BSD (商用利用可能) | LZ77方式圧縮解凍 (全新規実装) |
| MXDRV | X68的default (milk., K.MAEKAWA, Missy.M, Yatsube) | オリジナルMXDRVドライバ |
| KH-Dot-Kodenmachou-16 | 柿木フォント | ドットフォント |

> ソース元: `MDXPlayer-main` (iOS 版 MDX プレーヤー) の C++ エンジン部分を macOS 向けに流用。
> オリジナル実装: `Vendor/opm/` (OPM) と `Vendor/lzx/` (LZX) に配置。コード流用せず最適化されたクリーンな実装。
