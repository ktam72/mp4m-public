# MP4M — MDX Player for macOS

macOS向けのMDXプレイヤー。MDX/PDX 形式の音楽ファイルをリアルタイム再生し、スペクトラムアナライザー・レベルメーター・キーボード表示を持つマニアックなミュージックプレーヤーです。

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT%20%2B%20fmgen-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey)

## 特徴

- **MDX/PDX 完全サポート** — X68000 OPM FM 音源 + ADPCM サンプルの再生
- **リアルタイム可視化** — 32バースペアナ（ピーク保持）・16chレベルメーター・パン表示
- **ピアノキーボード表示** — FM 8ch 発音状態をピアノキーボード上に可視化
- **マルチコア対応** — Apple Silicon M Series の Performance コアを活用し、メインスレッド負荷を軽減
- **スレッドセーフ設計** — `os_unfair_lock` による排他制御で安全な並行アクセスを実現

## インストール

### ソースからビルド

```bash
cd MP4M
xcodegen generate
xcodebuild -project MP4M.xcodeproj -scheme MP4M -configuration Release build
```

**要件**: Xcode 15.0+, macOS 14.0+, Apple Silicon または Intel Mac

## App Store 配布について

**当プロジェクトは App Store での配布を予定していません。**

### 理由

**X68000 フリーウェアの著作権尊重**
   - 本プロジェクトは GAMDX（MXDRVG、pcm8、x68pcm8）など X68000 時代のフリーウェア資産を活用しています
   - これらの著作権者（GORRY、milk、K.MAEKAWA、m_puusan、Yosshin、Missy.M、Yatsube 等）のライセンス条項を厳密に遵守することを優先
   - App Store 配布による商用化は、著作権者の意図に反する可能性があり、採用していません





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

### 処理負荷軽減の実装対策
本アプリはローカル音楽再生時の処理負荷を最小限に抑えるため、以下の設計を採用しています：

- **マルチコア専用スレッドオフロード**: Apple Silicon M Series のPerformanceコアを活用し、MDX/PDXデコード・音声レンダリングを`Task.detached(priority: .userInitiated)`による高優先度バックグラウンドスレッドに移譲。メインスレッドのUI処理負荷を軽減し、60fpsの応答性を維持。
- **軽量排他制御**: スレッド間の共有データアクセスに`os_unfair_lock`を採用。従来のpthread_mutex等よりロック・アンロックのオーバーヘッドが小さく、並行処理時の遅延を最小化。
- **ストリーミング再生**: AVAudioSourceNodeによるリアルタイム音声レンダリングを採用。全ファイルをメモリに事前読み込みせず、再生に必要な分だけ逐次デコードすることで、メモリ使用量と初期読み込み負荷を抑制。
- **UI更新最適化**: Swift 6のObservationマクロを使用し、監視対象のプロパティが実際に変更された場合のみUIを再描画。無駄な再描画を防止し、レンダリング負荷を軽減。
- **可視化処理の最適化**: 32バー・スペクトラムアナライザーの更新頻度を音声サンプリングレートに同期させ、過剰な描画要求を回避。

### 検証結果
マルチスレッド改善の検証結果は以下の通りです：

- **CPU使用率**: アイドル時 0-3.7%, 再生時 5-8%（Apple Silicon）
- **メモリ使用量**: 1.2%（安定、変動なし）
- **データ競合**: Thread Sanitizer で検出なし
- **UI応答性**: 60fps フレームレート維持（レイアウト破損なし）

## セキュリティに関する注意

本アプリはローカル音楽再生に特化し、以下の脆弱性対策を実施しています：

- **サンドボックス厳格適用**: macOS App Sandbox を有効化し、権限は「ユーザー選択ファイルの読み取り専用」のみに限定。ネットワーク・デバイスアクセス等の不要な権限は一切付与なし
- **バッファオーバーフロー防止**: MDX/PDX ヘッダーのサイズ・値範囲チェック、LZX 解凍時の出力バッファ境界検証を実施。悪意ある改ざんファイルによるメモリ破壊を防止
- **シーケンスポインタ検証**: MDX 再生シーケンスのポインタ値を都度検証し、無限ループ・不正アドレスアクセスを防止
- **スレッドセーフ設計**: `os_unfair_lock` による排他制御と `Task.detached(priority: .userInitiated)` の適切な使用で、データ競合による未定義動作を回避
- **入力パス検証**: PDX ファイルのパスを検証し、同一ディレクトリ外へのアクセス（パストラバーサル）を防止
- **ユーザーデータ非収集**: ネットワーク権限を持たず、個人情報・利用履歴等のデータを一切収集・送信しません


## 関連プロジェクト

- [fmgen](https://github.com/kichikuou/fmgen) — YM2151 FM エミュレーター
- [GAMDX](https://gorry.haun.org/android/gamdx/) — GORRY の Android MDX プレーヤー（MXDRVG、pcm8/x68pcm8 公式リポジトリ）

## 編集後記

作者は1990年代、パソコン通信（草の根ネット）を通じてX68000のフリーウェアに触れ、充実した日々を過ごしました。その際に出会ったのがMDX形式の音楽データと、X68000用のグラフィカルプレイヤーの「mmdsp」です。これに出会ったときは衝撃的でした。

近年、macOS向けのMDXプレイヤーを探しましたが、iOS向けのものしか見つからず、macOS版が欲しいと感じていました。そこで最近AI駆動開発に興味を持ち、学習を兼ねて本プロジェクトを立ち上げました。

開発にあたっては、過去に触れたiOS向けMDXプレイヤーと、X68000時代のmmdspのUI/挙動をイメージし、懐かしさと現代的な技術を融合させることを目指しました。

それにしても、生成AIの力はすごいですね。私自身はXCODEもSWIFTもわからないのでコーディングをAIに任せられたのは非常に大きかったです。私自身はAI（主にClaude codeとBig Pickle）との対話に注力し、設計と動作確認結果のフィードバックを繰り返して品質を上げていきました。
お気づきの点がありましたらフィードバックいただけるとありがたいです。

---

**Last Updated**: 2026-05-06  
**Version**: 1.0 beta  
**macOS Requirement**: 14.0 Sonoma+  
**Build Tool**: Xcode 15.0+, xcodegen
