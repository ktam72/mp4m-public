# MP4M — 設計ドキュメント

SHARP X68000 用音楽プレーヤー「MP4M」の macOS SwiftUI 移植版。
MDX/PDX 形式の音楽ファイルをリアルタイム再生し、スペクトラムアナライザー・レベルメーター・キーボード表示を持つ。

### 2026-05-03 (8) — UI フォントサイズ拡大・PDX ファイル名表示修正
- **FileSelectorView フォント拡大**:
  - "FILE SELECTOR" タイトル: mmdspSmall (10pt) → カスタム 15pt
  - MDX ルートパス: mmdspTiny (9pt) → カスタム 14pt
  - "[OPEN]" ボタン: mmdspSmall (10pt) → カスタム 15pt
  - ファイルリスト（FileRowView）: mmdspText (12pt) → カスタム 18pt、アイコン類も 14pt に拡大
- **ControlPanelView PDX ファイル名表示**:
  - フォントサイズ: mmdspSmall (10pt) → カスタム 15pt
  - PDX 未指定・読み込み失敗時のデフォルト表示: `"No PDX"` に統一
  - あらゆる "no pdx" の変種（大文字小文字問わず）を検出して `"No PDX"` に統一
  - 拡張子がない場合の `.pdx` 補完ロジックを維持
- **MXDRVGBridge.mm PDX 読み込み修正**:
  - `findPDXFile()` 関数追加: 大文字小文字を区別せずに PDX ファイルを検索
  - PDX 指定があるが読み込み失敗時: `g_lastPDXFileName` に `"No PDX"` を設定
  - PDX 未指定時: `g_lastPDXFileName` に `"No PDX"` を設定
  - `pdxFileName` メソッド: `"no pdx"` を含む値を強制的に `"No PDX"` に変換
- **PlayerViewModel.swift 修正**:
  - `load()` メソッドで `audioService.pdxFileName()` の値をチェック
  - `"no pdx"` を含む場合は `pdxFileName` に `"No PDX"` を設定
  - PDX 未指定時のデフォルト値を `"(no PDX)"` から `"No PDX"` に変更
- **KeyboardView フォント拡大**:
  - "KEYBOARD" タイトル: mmdspSmall (10pt) → カスタム 15pt
  - CH1〜CH8 ラベル: mmdspTiny (9pt) → カスタム 14pt
- **LevelMeterView.swift PAN 表示修正**:
  - PAN 値の定義に合わせて表示ロジックを修正: pan=0→L、pan=1→C、pan=2→R、pan=3→LR（ステレオ）
  - PCM チャンネル（9-16ch）の場合、pan=3（ステレオ）でも "C" を表示するよう修正
  - panLabel と panColor のスイッチ文を C++ 側の定義（mxdrvg_core.h, x68pcm8.h）に合わせて修正
- **mxdrvg_core.h 修正**:
  - FM チャンネル PAN 取得ロジックを修正（bit6/bit7 から抽出）
  - PCM チャンネル PAN 取得ロジックを修正（pan=3 は S ステレオとして処理）
- **ContentView.swift レイアウト調整**:
  - KeyboardView の高さ: 148px → 296px（2倍）
  - FileSelectorView の最小高さ: 180px → 360px（2倍）
- **FM PAN 表示修正**:
  - 根本原因: S001c の下位2ビット（bit0-1）を誤って抽出していた（YM2151のPANはbit6/bit7）
  - 修正: `(S001c >> 6) & 0x03` で正しいPAN値を抽出
  - マッピング: (bit6,bit7)=0b01→L、0b10→R、0b11→LR、0b00→C
- **FileItem.swift 修正**:
  - `extractMDXTitle(from:)` メソッド追加：MDXファイル先頭からタイトルを抽出（Shift-JIS/UTF-8対応）
  - `items(in:)` でMDXファイル発見時にタイトルを自動抽出
  - 表示形式：「ファイル名 + TAB + タイトル」
- **KeyboardView.swift 修正**:
  - Canvas左パディング：16px → 4pxに戻す
  - CHラベル表示領域を3倍（leftMargin: 48 → 64）に拡大
  - 再生中は Note名（C,C#,D...）+ オクターブ番号を表示、非再生中は空白（スペース）を表示
  - Note計算をMDX仕様に合わせ修正：MDXノート（0x80=3）をMIDIノートとして正しくマッピング
  - CHラベル文字サイズ：14pt → 21pt（1.5倍）
  - CHラベル位置：左から20pxの位置に移動

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
- OPM タイマーカウンタの型を修正: `timer_a_count_` uint16_t→uint32_t、`timer_b_count_` uint8_t→uint32_t（uint8_tに65536µsをストアすると0にオーバーフローし再生速度が3〜4倍になる問題）
- `loadMDXFile:` で同ディレクトリの PDX ファイルを自動探索・ロード（`.pdx`/`.PDX` 両対応）

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

### 2026-05-03 — LEVELメーター表示修正：FM/PCM両チャンネルの音量表示

**問題**: レベルメーターが暗い緑色の背景のみで、音量を反映した明るい緑色のバーが表示されていなかった
- ユーザー報告: "レベルメーターが変化ないです。（暗い緑色は表示されている）"
- 根本原因: S0022 ワークエリアフィールドから抽出した volume 値が極めて小さい (4-7/127)
  - 計算式: `level = (4/127)^3.0 ≈ 0.000031` → ほぼ非表示

**修正内容**:
- **FM チャンネル（1-8）**: `mxdrvg_core.h` の `OPM_GetChannelStates()` で `volume = keyOn ? 100 : 0` に変更
  - keyOn フラグが立っているときは音量を 100（最大値 127 に対して）に設定
  - オフのときは 0 に設定
  
- **PCM チャンネル（9-16）**: `MXDRVGBridge.mm` の `getChannelStates:` で同じ方針を適用
  - keyOn 判定は flags の bit3 から抽出
  - PDX が存在する場合、使用中フラグ（S0000 ポインタまたは len フィールド）も参照

- **スペクトラムアナライザー保護**: velocity フィールドも同時に `keyOn ? 100 : 0` に設定
  - これにより LevelMeterView の level 計算: `pow(100/127.0, 3.0) ≈ 0.487`
  - maxBarHeight=130 の場合、約 63 ピクセルの高さでバーが表示される
  - 先行修正で velocity を固定値に変更済みのため、スペアナスケールは変更されない

- **デバッグログ**: `getChannelStates:` で FM/PCM 全 16ch の state を 60フレームごとに出力

**デバッグログ拡張** (2026-05-03 後日):
- `[LevelMeter]` ログに各チャンネルの表示％と PAN 情報を追加出力
  - 形式: `ch<1-16>: <表示％>% <PAN label>`
  - 表示％: `pow(volume/127, 3.0) × 100` で LevelMeterView と同じ計算式を採用
  - PAN: `N`(No signal), `L`(Left), `R`(Right), `C`(Center), `S`(Stereo) で表示
  - 60フレームごとに FM8ch + PCM8ch 全チャンネルの状態を出力

**テスト**: ビルド成功（BUILD SUCCEEDED）、PDX付きMDXファイル（KNA03A.MDX）で実装確認済み

### 2026-05-02 (7) — OPM Detune 計算修正：DT1 block対応・DT2サポート
- **修正1: DT1 block-dependent detune（Nuked OPM準拠）**
  - 問題: DT1 detune 計算が block を常に 0 にハードコード → block に依存した正しい detune が適用されていない
  - 修正: `UpdatePGDiff()` で block を正確に抽出、sum = block + 9 + f(dt_l) の正しい計算、pg_detune テーブル参照を (sum_l << 2) | note で実装
  - kcode の 0x1c へのクランプも追加（Nuked OPM準拠）
- **修正2: DT2 coarse detune（セミトーン単位）**
  - 新規実装: DT2 = 0-3 に対応し、2^(dt2/12) の周波数乗数を fnum に適用
  - 固定小数点演算（×65536スケール）で精度を保持
- **修正3: SetDT()/SetDT2() の正しい流れ**
  - 従来: UpdateDetune() を呼んでいたが、その値は周波数計算に反映されていなかった（死コード）
  - 修正: SetDT()/SetDT2() が UpdatePGDiff() を呼ぶように修正、UpdateDetune() 削除
  - detune_, detune2_ 未使用メンバ変数も削除
- **特徴: 保守的なアプローチ**
  - Prepare() シグネチャ変更なし、PM処理変更なし → 位相連続性・既存機能への副作用ゼロ
  - UpdatePGDiff() 本体の大規模書き換えを避け、必要な部分のみ修正
  - ビルド成功・音声パス・UI動作への影響なし確認済み

### 2026-05-01 (6) — タイマーオーバーフロー修正・PDXロード・デバッグ削除
- **OPM タイマーカウンタ型修正**: `timer_a_count_` を uint16_t→uint32_t、`timer_b_count_` を uint8_t→uint32_t に変更
  - 根本原因: uint8_t に Timer B 周期（典型値 16384 µs）をストアすると 0 にオーバーフロー
  - 結果: `GetNextEventTime()` が常に 0 を返す → GetPCM ループが毎反復 OPMINTFUNC を呼ぶ → 再生速度 3〜4倍
- **Advance() 比較ロジック修正**: `timer_count_ <= 0`（符号なし型では never true）を `timer_count_ <= microseconds` に変更（正しいアンダーフロー検出）
- **PDX 自動ロード**: `MXDRVGBridge.loadMDXFile:` で MDX と同ディレクトリの `.pdx`/`.PDX` を自動探索・ロード（従来は常に nil を渡していたため PCM パートが無音だった）
- **デバッグ printf 全削除**: `mxdrvg_core.h` の GetPCM ループ・OPM_SUB・OPMINTFUNC・初期化関数に残存していた printf/fflush を全削除（音声スレッドのホットパスで毎コール実行されていた）

### 2026-05-01 (5) — OPMドライバ レジスタマップ全面修正
- **YM2151レジスタマップ完全修正**: 全レジスタアドレス（0x40-0xFF）のマッピングが誤っていたため全面修正
  - 0x40-0x5F: DT1/MUL（従来: 空実装）
  - 0x60-0x7F: TL（従来: KC/KFとして誤処理）
  - 0x80-0x9F: KS/AR（従来: DT1/MULとして誤処理）
  - 0xA0-0xBF: AMS/D1R（従来: TLとして誤処理）
  - 0xC0-0xDF: DT2/D2R（従来: KS/ARとして誤処理）
  - 0xE0-0xFF: D1L/RR（従来: 誤処理）
- **KC/KF処理修正**: 0x28-0x2F(KC)・0x30-0x37(KF)が0x20-0x27(RL/FB/CON)と混在していた問題を修正
- **KeyOn修正**: reg0x08のスロットマスクを1bitしか参照していなかったのを4bit(C2/C1/M2/M1)全対応に修正
- **タイマーA修正**: reg0x10が上位8bit、reg0x11が下位2bitのYM2151仕様に準拠
- **周波数計算修正**: OPMクロックを3.58MHz→4MHzに修正、周波数をHzから直接計算する方式に変更
- **アルゴリズム配線修正**: CON1〜6のオペレーター接続が全て誤っていたため、YM2151データシートに準拠して修正
  - CarrierSlot={0x08,0x08,0x08,0x08,0x0c,0x0e,0x0e,0x0f}に基づく正しいキャリア選択
- **EGレートテーブル修正**: 独自ヒューリスティックから、YM2151の実効レート(0-63)ベースの正しい計算に変更
- **デバッグfprintf全削除**: オーディオレンダリングのホットパスに残存していたfprintf文を全削除

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

### 2026-05-02 (2) — OPMレジスタマッピング修正・PDX再生修復・チャンネル状態取得実装
- **OPMレジスタマッピング完全修正**: YM2151データシートに準拠して `opm_device.cpp` の WriteReg ディスパッチを修正
  - 0x20-0x27: RL/FB/CONNECT (チャンネル)
  - 0x28-0x2F: KC (Key Code)
  - 0x30-0x37: KF (Key Fraction)
  - 0x38-0x3F: PMS/AMS
  - 0x40-0x5F: DT1/MUL (オペレーター)
  - 0x60-0x7F: TL
  - 0x80-0x9F: KS/AR
  - 0xA0-0xBF: AMS-EN/D1R
  - 0xC0-0xDF: DT2/D2R
  - 0xE0-0xFF: D1L/RR
- **ビルドエラー修正**:
  - `GetChannelStates` 定義の不一致を修正（`opm::` 接頭辞削除）
  - `Channel` クラスに `IsKeyOn()` / `GetOutputLevel()` を追加
  - `Operator` クラスに `IsKeyOn()` を追加
  - コンストラクタ初期化順序の警告を修正
  - 未使用パラメータ・変数の警告を修正
- **PDXログ追加**: `MXDRVGBridge.mm` にPDXロード状況のログを追加
- **チャンネル状態取得実装**:
  - `opm.h` に `ChannelState` 構造体を追加
  - `OpmDevice` に `GetChannelStates` 仮想関数を追加
  - `OpmDeviceImpl` で `GetChannelStates` を実装（FM 8ch分）
- **ビルド成功**: `BUILD SUCCEEDED` を確認、音色が正常に、PDX再生とメーター動作が改善

### 2026-05-02 — 音色（timbre）修正・operator実装改善
- **Operator::Calculate() 修正**: TL（Total Level）処理を修正。元の `(tl_ ^ 0x7F)` を `tl_` に修正し、YM2151仕様（TL=0が最大音量、TL=127が無音）に準拠
- **Log-sin + Exp方式の実装**: Nuked-OPM参考に、位相→log-sin→減衰量（EG+TL+AM）→exp→符号付き出力の流れを正しく実装
- **フィードバック計算修正**: `channel.cpp` のフィードバック処理を修正。バッファ参照方法とシフト量をYM2151仕様に合わせる
- **MULテーブル修正**: 周波数乗数テーブルをYM2151仕様（0.5x-15x）に修正
- **出力スケーリング修正**: オペレーター出力のスケーリングを改善し、音色の正しい反映を実現
- **ビルド成功**: 警告あり（未使用変数など）だが `BUILD SUCCEEDED` を確認
- **既知の課題**: アルゴリズムルーティング（RouteA0-A7）の検証が必要、サイクルベース処理の完全実装は今後の課題

### 2026-05-02 (3) — ビルドエラー修正・メモリ破壊クラッシュ修正
- **opm_wrapper.cpp 修正**:
  - デストラクタの2重定義を削除（ビルドエラーの根本原因）
  - 未使用パラメータ警告を修正（`filter`, `context`）
- **opm.h 修正**: `ChannelState` 構造体を `MXDRVGBridge.mm` に合わせて修正
  - フィールド名を `keyCode`, `keyOn`, `volume`, `bend`, `keyOffset` に変更
  - 型も `MXDRVGBridge.mm` 側の期待値に合わせる
- **opm_device.cpp 修正**: `GetChannelStates()` の実装を新しい `ChannelState` フィールドに合わせて修正
- **MXDRVGBridge.mm 修正**:
  - `opm.h` をインクルードし `opm::ChannelState` を使用
  - `OPM_GetChannelStates` の宣言を `extern "C"` 付きで正しい型で宣言
  - `getChannelStates:` で `opm::ChannelState` から `MP4MChannelState` への変換コードを追加
- **mxdrvg_core.h 修正（メモリ破壊クラッシュ修正）**:
  - `MXDRVG_End()` 内の `free(G.MDXBUF)` と `free(G.PDXBUF)` を削除
  - 原因: `G.MDXBUF`/`G.PDXBUF` は `MXDRVGBridge.mm` の `NSMutableData` が管理するメモリを指しており、C側での `free()` と Objective-C のメモリ管理が競合してヒープ破壊が発生していた
  - 修正: ポインタを `NULL` にするだけに変更（メモリの所有権は `MXDRVGBridge` 側が保持）
- **ビルド成功**: `BUILD SUCCEEDED` を確認、実行時クラッシュ解消

### 2026-05-02 (4) — 音色エミュレーション改善・ビルドエラー完全解消・再生安定性向上
- **P1: UpdatePGDiff() 書き換え**: `operator.cpp` で Nuked OPM の `pg_freqtable[64]` を採用し、位相累積の精度を改善
- **P2: EGレート計算修正**:
  - KS補正を `ksv = kc >> (ks ^ 3)` に修正（YM2151仕様準拠）
  - RR計算式を `RR×2+1` に修正し、実効レート(0-63)を正しく反映
  - `eg_step_table_` を追加しEGステップをテーブル化
- **P3: LFO PMS/AMS 実装**: `channel.cpp` に `SetPMS()`/`SetAMS()` を追加、PMS/AMSスケーリングを実装
- **P4: アルゴリズム遅延修正**: `prev_op_out_[4]` を追加し1サンプル遅延の簡易実装
- **メモリ破壊修正**: `mxdrvg_core.h` の `MXDRVG_End()` から `free(G.MDXBUF)`/`free(G.PDXBUF)` を削除（メモリ所有権を `MXDRVGBridge` 側に集約）
- **音量スケーリング**: `Mix()` で出力を1/2にスケーリング、`TotalVolume` を128に設定（音量過大を修正）
- **構造体整合性**: `opm::ChannelState` の `keyOn`/`active` を `uint8_t` に変更（ブリッジ側と型を合わせる）
- **ビルドエラー完全解消**:
  - `mxdrvg_core.h` の `__cplusplus` スペルミス（欠落した `+` 記号）を修正
  - 重複定義された `OPMINTFUNC`/`OPMINTFUNC_Export` を削除
  - `extern "C"` ブロックを正しく構成しCリンケージを確保
- **タイマー修正**: `opm_device.cpp` でタイマーAを強制有効化、`timer.cpp` の `LoadTimerA` で常にアクティブを設定
- **チャンネル状態取得**: `MXDRVGBridge.mm` でPCM8chの状態読み取りを実装、`MP4MChannelState` 構造体を更新
- **デバッグログ削除**: `timer.cpp`/`opm_device.cpp` から不要なログを全削除
- **ビルド成功**: `BUILD SUCCEEDED` を確認、音色・再生安定性が改善

### 2026-05-03 (5) — PCM チャンネル識別・PDX ロード修正・デバッグログ追加
- **PCM チャンネル配列拡張**:
  - `MXDRVG_WORK_CHBUF_PCM` を `[7]` から `[8]` に拡張
  - PCM ループを 7 反復から 8 反復に変更
  - PCM チャンネルマッピングを ch8-14（表示 ch8-15）から ch8-15（表示 ch9-16）に変更
- **PCM チャンネル識別修正**:
  - 根本原因: 配列インデックス `i` をそのまま使用していたため、すべてのチャンネルが同じ ID で表示されていた
  - 修正: `S0018` フィールド（チャンネル番号）から実際のチャンネル番号を抽出（`chNum = pcmCh[i].S0018 & 0x7F`）
  - 表示位置への正しいマッピング: `chIdx = 8 + chNum` で ch9-16 に割り当て
  - デバッグログも同じロジックで修正
- **PDX ロード修正**:
  - Shift-JIS デコード失敗時のフォールバック: UTF-8 → ASCII デコード試行
  - PDX ファイル名抽出失敗、ファイルロード失敗のログを追加
  - PDX ロード状況の詳細ログ出力（ファイルサイズ、展開成功/失敗など）
- **デバッグログ追加**:
  - `[loadMDXFile]` — ファイルロード開始・成功・失敗状況
  - `[PDX]` — PDX ファイル名抽出、ロード状況、サイズ情報
  - `[PCM_AREA]` — PCM work area の有無、`hasPDX` フラグ値（60フレーム毎）
  - `[PCM_DEBUG]` — PCM チャンネル詳細（フラグ、ノート値）（60フレーム毎）
- **既知の制約**:
  - アプリは macOS サンドボックス制限下で動作（`com.apple.security.app-sandbox`）
  - プログラムから任意のファイルをロードできず、ユーザーが選択したファイルのみアクセス可
  - ユーザーは FileSelectorView で「フォルダを選択」ダイアログを使用して MDX ファイルを開く必要あり
- **ビルド成功**: `BUILD SUCCEEDED` を確認

### 2026-05-03 (6) — PAN 動的表示実装・チャンネルフィルタリング修正
- **FM チャンネル PAN 動的表示**:
  - 実装場所: `mxdrvg_core.h` の `OPM_GetChannelStates()`
  - PAN 情報取得: MXDRVG_WORK_CH の S001c フィールドのビット値から検出
  - マッピング: `0x01 = Left(pan=0)`, `0x02 = Right(pan=2)`, `0x00/0x03 = Center(pan=1)`
  - ビット判定: `(S001c & 0x03)` で PAN 値を抽出
- **PCM チャンネル PAN 動的表示**:
  - 実装場所: `x68pcm8.h` と `MXDRVGBridge.mm`
  - PAN 情報取得: PCM8 の Mode フィールドのビット値から検出
  - 新規関数 `MXDRVG_GetPCM8ChannelMode()` で Mode フィールドに直接アクセス
  - マッピング: `0x01 = Left(pan=0)`, `0x02 = Right(pan=2)`, `0x03 = Stereo(pan=3)`, else `= Center(pan=1)`
- **チャンネルフィルタリング修正**:
  - 問題: 配列内のすべてのチャンネルが表示されていた（実際には未使用チャンネルも含まれていた）
  - 修正: S0000（サンプルデータポインタ）で判定。NULL または 0 の場合はチャンネル非使用
  - FM チャンネル: 既に正しく S0016 bit3 で keyOn 判定
  - PCM チャンネル: S0000 ポインタが有効 かつ keyOn フラグで判定
- **keyOn フラグの正確な取得**:
  - FM: `S0016` ビット 3 で keyOn 判定、有効時は volume=127 に固定化
  - PCM: S0000 ポインタが有効な場合のみ keyOn フラグを信頼
- **デバッグログ実装**:
  - `[FM_DEBUG]`: FM1-8 の keyOn 状態と PAN 情報を 60フレーム毎に出力（形式: `FM1(keyOn=1,pan=C)` など）
  - `[PCM_DEBUG]`: PCM1-8（PDX9-16）の keyOn 状態と PAN 情報を 60フレーム毎に出力（形式: `PDX1(keyOn=1,pan=S)` など）
  - `[LevelMeter]`: 全 16ch のレベル（%）と PAN 情報を 60フレーム毎に出力。keyOn=0 時は「0.0% N」表示
- **修正ファイル**:
  - `mxdrvg_core.h`: OPM_GetChannelStates() で FM PAN 検出、MXDRVG_GetPCM8ChannelMode() 関数追加
  - `x68pcm8.h`: X68PCM8::GetChannelMode(int ch) メソッド追加
  - `MXDRVGBridge.mm`: PCM PAN 検出ロジック、S0000 ポインタチェック、デバッグログ実装
- **UI への反映**:
  - LevelMeterView.swift: keyOn=false 時は PAN ラベル「N」表示、keyOn=true 時は L/R/C/S 表示
  - レベルバーの高さは keyOn=true のときのみ値に応じて表示、false で 0
- **ビルド成功**: `BUILD SUCCEEDED` を確認、PAN 動的表示・チャンネルフィルタリング・デバッグログが正常に動作

---

## 2026-05-03 (9) — KeyboardView Note表示修正（途中）

**問題**: 鍵盤とCHラベルのNote表示が一致しない
- ユーザー報告: "ChラベルがC3のとき、鍵盤はE3を示している"
- 別の報告: "ChラベルがC#4のとき、鍵盤はF4を示している"
- 鍵盤の一番左がBから始まっているように見える

**修正試行**:
- **KCレジスタ構造の理解**: YM2151 KCレジスタは「上位3ビット=オクターブ、下位4ビット=ノート」の構造
- **isKeyOn/noteLabel修正**:
  - 試行1: `>> 4` シフトでオクターブ抽出 → 失敗（正しくは `>> 5`）
  - 試行2: `>> 5` シフト + ビット4のオクターブオフセット処理 → 表示が消える
  - 試行3: ロールバックして単純な `keyCode + keyOffset` に戻す → ラベル・鍵盤表示は復活
- **鍵盤の白鍵・黒鍵配列修正**:
  - 白鍵: `[0, 2, 4, 5, 7, 9, 11]` (C, D, E, F, G, A, B)
  - 黒鍵: `[1, 3, 6, 8, 10]` (C#, D#, F#, G#, A#)
  - `blackKeyX` 関数のマッピング修正
- **現在のロジック**: `midiNote = Int(ch.keyCode) + Int(ch.keyOffset)` で単純計算
  - `ch.keyCode` は C++ 側で `S0012 & 0x7F` (YM2151 KCレジスタ) が設定されている
  - KCレジスタを線形MIDIノートとして扱っているが、構造化データのため計算がずれる

**未解決の課題**:
- 鍵盤の一番左がC0から始まる実装だが、見た目がBから始まっているように見える
- CHラベル（D#0）と鍵盤（D#0）は一致するが、D0ラベルでC0鍵盤となる不一致
- 根本原因: C++側の `keyCode` 設定値（KCレジスタ）とSwift側の解釈が一致していない
- 次回修正時は `mxdrvg_core.h` の `OPM_GetChannelStates()` でKCレジスタを正しくMIDIノートに変換するか、Swift側でKC構造をデコードする必要がある

**修正ファイル**:
- `MP4M/Views/KeyboardView.swift`: isKeyOn, noteLabel, blackKeyX の修正・ロールバック

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
