# Vendor フォルダ構成とビルド使用ファイル

## 目的

Xcode プロジェクト（MP4M）で実際にビルドに使用しているファイルと、Vendor フォルダ内の物理的なファイル構成を一致させること。

これにより、エクスプローラ（Finder）から「何がビルドに必要か」が一目でわかる状態にする。

## 背景（2026-05 時点）

- `Vendor/gamdx/` は元々 Android NDK プロジェクト（jni/ 構造）のコードをそのまま取り込んだ
- `project.yml` で `includes:` により必要なファイルだけを明示指定していたため、ビルド自体は正しく動作していた
- しかし、エクスプローラ上では Android 向け設定ファイル（Android.mk, Application.mk）、ビルドスクリプト（mk*.sh）、未使用ヘッダ、データファイルなどが混在しており、見通しが非常に悪かった

## ビルドに実際に使用しているファイル

### コンパイル対象のソースファイル（10ファイル）

| ファイル | 役割 | 備考 |
|---------|------|------|
| `Vendor/gamdx/jni/mxdrvg/so.cpp` | MXDRVG 本体（MDX 再生エンジン） | メインのエミュレーション処理 |
| `Vendor/gamdx/jni/pcm8/pcm8.cpp` | PCM8 エミュレーション | PCM 音源のエミュレーション |
| `Vendor/gamdx/jni/pcm8/x68pcm8.cpp` | X68000 PCM8 互換層 | `mxdrvg_core.h` から参照 |
| `Vendor/gamdx/jni/downsample/downsample.cpp` | ダウンサンプリング | `mxdrvg_core.h` から参照 |
| `Vendor/gamdx/jni/fmgen/fmgen.cpp` | FM 音源ジェネレータ | fmgen ライブラリ本体 |
| `Vendor/gamdx/jni/fmgen/fmtimer.cpp` | FM タイマー | タイマー割り込みエミュレーション |
| `Vendor/gamdx/jni/fmgen/opm.cpp` | OPM レジスタ実装 | YM2151 (OPM) のエミュレーション |
| `Vendor/lzx/lzx.cpp` | LZX 展開 | PDX ファイルの展開に使用 |
| `Vendor/ymfm/opm_wrapper.cpp` | ymfm ラッパー | ymfm エンジンへのブリッジ |
| `Vendor/ymfm/ymfm_opm.cpp` | ymfm OPM 実装 | 代替 FM エンジン（オプション） |

### 必須ヘッダファイル（インクルード依存）

**gamdx/jni/ 配下**:

- `types.h` — 共通型定義（**ymfm 側からも参照**されているため必須）
- `mxdrvg/mxdrvg.h`, `mxdrvg_core.h`, `mxdrvg_depend.h`
- `pcm8/pcm8.h`, `pcm8/x68pcm8.h`, `pcm8/global.h`
- `downsample/downsample.h`, `downsample/global.h`
- `fmgen/fmgen.h`, `fmgen/fmtimer.h`, `fmgen/opm.h`, `fmgen/OpmEngineFmgen.h`
- `fmgen/headers.h`, `fmgen/misc.h`, `fmgen/fmgeninl.h`

**ymfm/ 配下**（すべて必須）:

- `ymfm.h`, `ymfm_fm.h`, `ymfm_fm.ipp`
- `ymfm_opm.h`, `ymfm_opm.cpp`（ソース）
- `opm_wrapper.h`, `opm_wrapper.cpp`（ソース）
- `OpmEngineYmfm.h`, `IOpmEngine.h`

**lzx/ 配下**:

- `lzx.h`, `lzx.cpp`（ソース）

### ドキュメント（意図的に残している）

- `Vendor/gamdx/jni/fmgen/readme.txt` — fmgen ライブラリのオリジナル readme

## 削除したファイル（2026-05 整理）

| ファイル | 種別 | 削除理由 |
|---------|------|---------|
| `Android.mk` | Android NDK 設定 | macOS ビルドで一切使用しない |
| `Application.mk` | Android NDK 設定 | 同上 |
| `mkc.sh`, `mkd.sh`, `mkr.sh` | シェルスクリプト | Android ビルド用スクリプト |
| `fmgen/diag.h` | 未使用ヘッダ | どこからも `#include` されていない |
| `.DS_Store`（3箇所） | macOS 隠しファイル | 不要 |

**削除対象から除外したもの（または復元したもの）**:

- `types.h` — `ymfm/opm_wrapper.h` からも参照されているため残した
- `fmgen/readme.txt` — ユーザーの指示によりドキュメントとして保持
- `downsample/lowpass_44.dat`, `lowpass_48.dat` — **一度削除したが復元**（`downsample/global.h` が `#include "lowpass_*.dat"` で直接参照していたため必須）

### 教訓: データファイルのインクルードパターン

`downsample/global.h` は以下のようにデータファイルを直接インクルードしている:

```c
static const int16_t lowpass_44[] = {
    #include "lowpass_44.dat"
};
```

このため、通常の C++ ソースからの `#include` 検索では検出できず、ビルド時に初めて欠落が発覚した。

**ヘッダ依存調査時は、`.h` ファイル内の `#include` も必ず確認すること**。

## 削除後のディレクトリ構造

```
Vendor/
├── gamdx/
│   └── jni/                    ← Android NDK 由来の命名は残存（今後の見直し対象）
│       ├── downsample/
│       │   ├── downsample.cpp
│       │   ├── downsample.h
│       │   └── global.h
│       ├── fmgen/
│       │   ├── fmgen.cpp
│       │   ├── fmgen.h
│       │   ├── fmgeninl.h
│       │   ├── fmtimer.cpp
│       │   ├── fmtimer.h
│       │   ├── headers.h
│       │   ├── misc.h
│       │   ├── opm.cpp
│       │   ├── opm.h
│       │   ├── OpmEngineFmgen.h
│       │   └── readme.txt       ← ドキュメントとして保持
│       ├── mxdrvg/
│       │   ├── mxdrvg.h
│       │   ├── mxdrvg_core.h
│       │   ├── mxdrvg_depend.h
│       │   └── so.cpp
│       ├── pcm8/
│       │   ├── global.h
│       │   ├── pcm8.cpp
│       │   ├── pcm8.h
│       │   ├── x68pcm8.cpp
│       │   └── x68pcm8.h
│       └── types.h              ← ymfm からも参照されている重要ファイル
├── lzx/
│   ├── lzx.cpp
│   └── lzx.h
└── ymfm/
    ├── IOpmEngine.h
    ├── OpmEngineYmfm.h
    ├── opm_wrapper.cpp
    ├── opm_wrapper.h
    ├── ymfm.h
    ├── ymfm_fm.h
    ├── ymfm_fm.ipp
    ├── ymfm_opm.cpp
    └── ymfm_opm.h
```

## 今後のメンテナンス指針

### 新しいファイルを追加するとき

1. `project.yml` の `sources` セクションに `includes:` で明示的に追加する
2. 不要なファイル（Android 向け設定など）は最初から入れない
3. ヘッダの依存関係を必ず確認し、`types.h` のような共通ヘッダは安易に移動しない

### フォルダ構成の見直し（将来の検討事項）

現在の `Vendor/gamdx/jni/` という命名は Android NDK 由来で、macOS プロジェクトとしては違和感がある。

以下のような整理を将来的に検討可能：

- `Vendor/gamdx/src/` へのリネーム（`project.yml` と全 `#include` パスの修正が必要）
- または、fmgen / pcm8 / mxdrvg などを `Vendor/` 直下にフラットに配置
- 元の Android プロジェクト構造を `_original/` や git submodule で別管理

この整理を行う場合は、**すべての `#include` パスと `project.yml` の `HEADER_SEARCH_PATHS` を更新**する必要がある。

## 関連ファイル

- `project.yml` — XcodeGen 設定（sources / HEADER_SEARCH_PATHS）
- `MP4M.xcodeproj/project.pbxproj` — 生成後の Xcode プロジェクト（手動編集禁止）
- `MP4M/Bridge/MXDRVGBridge.mm` — 主要なブリッジコード（インクルード元）

---

**最終更新**: 2026-05-30
**実施者**: Claude (整理作業) + ユーザー承認
