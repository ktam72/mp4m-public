# MP4M — macOS MDX Player

SHARP X68000 用音楽プレーヤー「MP4M」の macOS SwiftUI 移植版。MDX/PDX 形式の音楽ファイルをリアルタイム再生し、スペクトラムアナライザー・レベルメーター・キーボード表示を持つマニアックなミュージックプレーヤーです。

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT%20%2B%20fmgen-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey)

## 特徴

- **MDX/PDX 完全サポート** — X68000 OPM FM 音源 + ADPCM サンプルの再生
- **リアルタイム可視化** — 32バースペアナ（ピーク保持）・16chレベルメーター・パン表示
- **ピアノキーボード表示** — 8chFM 発音状態をキーボード上に可視化
- **マルチコア対応** — Apple Silicon M1/M2/M3 の Performance コアを活用し、メインスレッド負荷を軽減
- **スレッドセーフ設計** — `os_unfair_lock` による排他制御で安全な並行アクセスを実現
- **X68000 風UI** — ドットフォント KH-Dot-Kodenmachou-16 による懐かしのルックアンドフィール

## インストール

### 方法1: バイナリダウンロード（推奨）

1. [GitHub Releases](https://github.com/ktam72/MP4M/releases) から最新の `MP4M.app.zip` をダウンロード
2. zip を解凍し、`MP4M.app` を Applications フォルダにドラッグ&ドロップ
3. Finder で MP4M.app を右クリック → "開く" を選択（初回のみセキュリティ確認が表示されます）

### 方法2: ソースからビルド

```bash
cd MP4M
xcodegen generate
xcodebuild -project MP4M.xcodeproj -scheme MP4M -configuration Release build
```

**要件**: Xcode 15.0+, macOS 14.0+, Apple Silicon (M1/M2/M3+) または Intel Mac

## 使い方

1. **フォルダを開く**：ウィンドウ左下の「[OPEN]」ボタンをクリックし、MDX ファイルが格納されたフォルダを選択
2. **ファイルを選択**：リストから再生したい MDX ファイルを選択
3. **再生**：「▶」ボタンで再生開始（スペースキーでも可）
4. **チャンネルミュート**：LEVELメーターのチャンネル番号をダブルクリックでミュート/ミュート解除
5. **ループ設定**：UI右下の数値でループ回数を指定（0-9回）
6. **オートモード**：「NORMAL」「AUTO」「SHUFFLE」で自動再生モード切り替え

### キーボード操作

| キー | 機能 |
|------|------|
| Space | 再生/一時停止 |
| ← / → | 前の曲 / 次の曲 |
| ↑ / ↓ | ボリュームアップ / ダウン |

### ファイル形式

- **MDX** — MXDRV 形式 (X68000 OPM FM 音源)
- **PDX** — ADPCM サンプルデータ (MDX と同ディレクトリに配置で自動ロード)

**注意**: ZMD/ZDF 形式（ZMUSIC）には対応していません。

## 技術スタック

| 要素 | 技術 |
|------|------|
| **UI** | SwiftUI 6.0 + Swift 6.0 (Observation マクロ) |
| **アーキテクチャ** | MVVM (`PlayerViewModel` + `FileBrowserViewModel`) |
| **音声処理** | AVAudioEngine + AVAudioSourceNode（リアルタイムレンダリング） |
| **マルチスレッド** | `Task.detached(priority: .userInitiated)` + `os_unfair_lock` |
| **MDX デコード** | MXDRVG (C++) + ObjC++ ブリッジ |
| **FM エミュレーション** | fmgen (cisc) — YM2151 オペレーター合成 |
| **PCM/ADPCM** | pcm8 (X68000 互換デコーダ) |
| **LZX 解凍** | オリジナル実装 (0BSD) |
| **フォント** | KH-Dot-Kodenmachou-16 (ドットフォント) |
| **プロジェクト管理** | xcodegen + project.yml |

## パフォーマンス

マルチスレッド改善（フェーズ1）検証済み：

- **CPU使用率**: アイドル時 0-3.7%, 再生時 5-8%（Apple Silicon M系）
- **メモリ使用量**: 1.2%（安定、変動なし）
- **データ競合**: Thread Sanitizer で検出なし
- **UI応答性**: 60fps フレームレート維持（レイアウト破損なし）

## ライセンス

このプロジェクトは複数のライブラリを組み込んでいます。ライセンス情報は以下の通りです：

### 使用しているオープンソースライブラリ

| ライブラリ | ライセンス | 著作権 |
|---|---|---|
| **fmgen** | cisc著作権 (フリーソフト配布) | [kichikuou/fmgen](https://github.com/kichikuou/fmgen) |
| **MXDRVG** | Apache 2.0 | GORRY（MDXPlayer-main より） |
| **pcm8/x68pcm8** | Apache 2.0 | GORRY（MDXPlayer-main より） |
| **LZX解凍** | 0BSD (商用利用可能) | MP4M プロジェクト |
| **KH-Dot-Kodenmachou-16** | 柿木フォント | 柿木定吉 |

### fmgen ライセンス詳細

fmgen は cisc により著作権が保持されています。以下の条件で自由に利用可能です：

1. **改変・組み込み・配布・利用**: 自由
2. **ただし以下が必須**:
   - 作者（cisc）と著作権を明記すること
   - 配布する際はフリーソフトと表示すること
   - ソースコード改変は改変内容を明示すること
   - ソースコード配布時はこのライセンステキストをそのまま添付すること
3. **商用利用**: 商用ソフト・シェアウェアへの組み込みには事前に cisc に合意を得る必要があります

ライセンス原文: [fmgen/README.md](https://github.com/kichikuou/fmgen/blob/master/README.md)

### LZX解凍 (オリジナル実装)

MP4M プロジェクトで実装した LZX 解凍機能は 0BSD ライセンス下で公開されており、商用利用可能です。

## セキュリティに関する注意

- **サンドボックス対応**: macOS App Sandbox に対応し、許可されたフォルダのみアクセス可能
- **バッファオーバーフロー対策**: MDX/PDX ヘッダー解析・LZX展開で境界チェック実施
- **シーケンスポインタ検証**: 無限ループ・不正アドレスアクセスを防止

## よくある質問

**Q: iOS / iPad に対応していますか？**  
A: 現在 macOS のみ対応です。iPad 対応は UI レイアウトの複雑性（縦向き固定対応など）が課題のため、現在実装を見送っています。

**Q: App Store で配布されていますか？**  
A: いいえ。署名・アイコン・メタデータ対応に 4-8 日の工数が必要なため、GitHub Releases での配布としています。

**Q: ZMD/ZDF (ZMUSIC 形式) に対応していますか？**  
A: いいえ。ZMUSIC デコーダー未実装のため非対応です。

**Q: 日本語以外の言語に対応していますか？**  
A: UI は日本語のみです。MDX ファイルのタイトルは Shift-JIS または UTF-8 でサポートされます。

## 開発・貢献

### ビルド（開発版）

```bash
cd MP4M
xcodegen generate
open MP4M.xcodeproj  # Xcode で開く
```

### デバッグログ

以下の環境で重要なデバッグ情報が stderr に出力されます：

```bash
# Terminal.app で実行（ログが表示される）
/Applications/MP4M.app/Contents/MacOS/MP4M
```

主なログ:
- `[PlayerViewModel.init]` — ViewModel 初期化
- `[LevelMeter]` — 全16ch のレベル・PAN 情報（60フレーム毎）
- `[FM_DEBUG]` / `[PCM_DEBUG]` — FM/PCM チャンネル状態
- `[PDX]` — PDX ロード状況

### テスト用 MDX ファイル

以下のアーカイブから公開 MDX ファイルを入手できます：

- [MDXMUSIC ライブラリ](http://www.firemans.net/) — 音楽作品集
- [MDX Resources](https://github.com/kichikuou/mdx-resources) — デモ曲

## 今後の予定

### 短期（検討中）
- iOS/iPad 対応（別UI分岐での実装）
- キーボードショートカット（フル実装）
- プレイリスト機能

### 長期（次フェーズ）
- ZMUSIC (ZMD/ZDF) サポート
- ドキュメントビューア（MDX/PDX の情報表示）
- プログラムプレイ

## 関連プロジェクト

- [MDXPlayer for iOS](https://github.com/kichikuou/mdxplayer-ios) — iOS 版 MDX プレーヤー（参考実装）
- [fmgen](https://github.com/kichikuou/fmgen) — YM2151 FM エミュレーター
- [MXDRVG](http://www.mxdrv.v.nrant.net/) — X68000 MXDRV ドライバ

## ライセンス表記

```
MP4M — macOS MDX Player
Copyright (c) 2026 ktam
Licensed under the MIT License, with fmgen library (cisc)

Includes:
- fmgen (cisc) — freely modifiable/distributable (商用は事前合意必須)
- MXDRVG (GORRY, Apache 2.0)
- LZX Decompression (0BSD, original implementation)
```

## 問い合わせ

不具合報告・機能リクエスト・セキュリティ脆弱性報告は以下までお願いします：

- GitHub Issues: [MP4M/issues](https://github.com/ktam72/MP4M/issues)
- Email: ktam72@gmail.com

---

**Last Updated**: 2026-05-03  
**Version**: 1.0 beta  
**macOS Requirement**: 14.0 Sonoma+  
**Build Tool**: Xcode 15.0+, xcodegen
