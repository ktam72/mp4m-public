# MP4M — macOS MDX Player

macOS向けのMDXプレイヤー。MDX/PDX 形式の音楽ファイルをリアルタイム再生し、スペクトラムアナライザー・レベルメーター・キーボード表示を持つマニアックなミュージックプレーヤーです。

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT%20%2B%20fmgen-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey)

## 特徴

- **MDX/PDX 完全サポート** — X68000 OPM FM 音源 + ADPCM サンプルの再生
- **リアルタイム可視化** — 32バースペアナ（ピーク保持）・16chレベルメーター・パン表示
- **ピアノキーボード表示** — 8chFM、8chPCM 発音状態をキーボード上に可視化
- **マルチコア対応** — Apple Silicon M1/M2/M3 の Performance コアを活用し、メインスレッド負荷を軽減
- **スレッドセーフ設計** — `os_unfair_lock` による排他制御で安全な並行アクセスを実現
- **X68000 風UI** — 懐かしのルックアンドフィール

## インストール

### ソースからビルド

```bash
cd MP4M
xcodegen generate
xcodebuild -project MP4M.xcodeproj -scheme MP4M -configuration Release build
```

**要件**: Xcode 15.0+, macOS 14.0+, Apple Silicon (M1/M2/M3+) または Intel Mac

## App Store 配布について

**当プロジェクトは App Store での配布を予定していません。**

### 理由

1. **X68000 フリーウェアの著作権尊重**
   - 本プロジェクトは GAMDX（MXDRVG、pcm8、x68pcm8）など X68000 時代のフリーウェア資産を活用しています
   - これらの著作権者（GORRY、milk、K.MAEKAWA、m_puusan、Yosshin、Missy.M、Yatsube 等）のライセンス条項を厳密に遵守することを優先
   - App Store 配布による商用化は、著作権者の意図に反する可能性があり、採用していません

2. **App Store 審査対応の余力がない**
   - 以下の審査項目への対応に相応のリソースが必要になります：
     - **プライバシー**: ユーザーデータ収集・追跡の詳細申告
     - **セキュリティ**: 暗号化、データ保護の体制構築
     - **コンテンツ**: 年齢制限、不適切コンテンツの事前確認
     - **パフォーマンス**: バッテリー消費、メモリリークの厳密チェック
     - **互換性**: macOS 全バージョン・デバイスでのテスト
     - **ユーザーサポート**: App Store 審査結果への対応、ユーザーレビュー対応
   - 現在のプロジェクトは個人開発のため、これらに対応する開発余力がありません

### 配布方法

MP4M は GitHub Releases でのみ配布します。最新版は以下からダウンロード可能です：
- **[GitHub Releases](https://github.com/ktam72/mp4m/releases)** — ソースコード・ビルド方法を提供

## 使い方

1. **フォルダを開く**：ウィンドウ左下の「[OPEN]」ボタンをクリックし、MDX ファイルが格納されたフォルダを選択
2. **ファイルを選択**：リストから再生したい MDX ファイルを選択
3. **再生**：「▶」ボタンで再生開始
4. **チャンネルミュート**：LEVELメーターのチャンネル番号をダブルクリックでミュート/ミュート解除
5. **ループ設定**：UI右下の数値でループ回数を指定（0-9回）
6. **オートモード**：「NORMAL」「AUTO」「SHUFFLE」で自動再生モード切り替え



### マウス操作

| 操作 | 機能 |
|------|------|
| 再生ボタンクリック | 再生/一時停止 |
| 前/次ボタンクリック | 前の曲 / 次の曲 |
| チャンネル番号ダブルクリック | チャンネルミュート |
| 音量スクロール | ボリュームアップ / ダウン |

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
| **MDX/PCM デコード** | GAMDX (MXDRVG, pcm8, x68pcm8) + ObjC++ ブリッジ |
| **FM エミュレーション** | fmgen (cisc) — YM2151 オペレーター合成 |
| **LZX 解凍** | オリジナル実装 (0BSD) |
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
| **GAMDX** (MXDRVG, pcm8, x68pcm8) | Apache 2.0 | [GORRY](https://gorry.haun.org/android/gamdx/) |
| **LZX解凍** | 0BSD (商用利用可能) | MP4M プロジェクト |

### fmgen ライセンス詳細

1. 本ソフトの由来(作者, 著作権)を明記すること.
2. 配布する際にはフリーソフトとすること．
3. 改変したソースコードを配布する際は改変内容を明示すること.
4. ソースコードを配布する際にはこのテキストを一切改変せずに
   そのまま添付すること．

ライセンス原文: [fmgen/readme.txt](https://github.com/kichikuou/fmgen/blob/master/readme.txt)

### LZX解凍 (オリジナル実装)

MP4M プロジェクトで実装した LZX 解凍機能は 0BSD ライセンス下で公開されており、商用利用可能です。

## セキュリティに関する注意

- **サンドボックス対応**: macOS App Sandbox に対応し、許可されたフォルダのみアクセス可能
- **バッファオーバーフロー対策**: MDX/PDX ヘッダー解析・LZX展開で境界チェック実施
- **シーケンスポインタ検証**: 無限ループ・不正アドレスアクセスを防止


## 関連プロジェクト

- [MDXPlayer for iOS](https://github.com/kichikuou/mdxplayer-ios) — iOS 版 MDX プレーヤー（参考実装）
- [fmgen](https://github.com/kichikuou/fmgen) — YM2151 FM エミュレーター
- [GAMDX](https://gorry.haun.org/android/gamdx/) — GORRY の Android MDX プレーヤー（MXDRVG、pcm8/x68pcm8 公式リポジトリ）
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

---

**Last Updated**: 2026-05-03  
**Version**: 1.0 beta  
**macOS Requirement**: 14.0 Sonoma+  
**Build Tool**: Xcode 15.0+, xcodegen
