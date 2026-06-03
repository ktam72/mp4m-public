# fmgen 改変内容

このドキュメントは、fmgenのreadme.txtに従い、cisc 氏による
オリジナルの fmgen ライブラリに加えたすべての変更を記述します。

## オリジナルソース

fmgen のオリジナルソースは GAMDX バンドルから取得しました。

公式配布元: https://gorry.haun.org/android/gamdx/

## 削除したファイル

| ファイル | 理由 |
|----------|------|
| `fmgen/opna.cpp` | YM2608/2610 (OPNA/OPNB) のサポート。OPM 専用のため不要 |
| `fmgen/opna.h` | 同上 |
| `fmgen/psg.cpp` | PSG 音源。OPM 専用のため不要 |
| `fmgen/psg.h` | 同上 |

## 追加したファイル

| ファイル | 目的 |
|----------|------|
| `OpmEngineFmgen.h` | IOpmEngine インターフェースを実装し、FM::OPM を MP4M のエンジン抽象化と接続するアダプタクラス |
| `headers.h` | stdio, stdlib, math, string, assert をまとめた便利ヘッダ |
| `misc.h` | GAMDX の common/misc.h から抽出したユーティリティ関数（Max, Min, Abs, Limit, BSwap, gcd, bessel0） |

## 構造変更

### ディレクトリのフラット化

変更前（`fmgen/` 下にネスト）:
```
fmgen/
  fmgen/
    fmgen.cpp  fmgen.h  fmgeninl.h
    fmtimer.cpp  fmtimer.h
    misc.h  opm.cpp  opm.h
    opna.cpp  opna.h  psg.cpp  psg.h
  OpmEngineFmgen.h  (追加)
  headers.h  (追加)
  misc.h  (追加)
```

変更後（フラット）:
```
fmgen/
  fmgen.cpp  fmgen.h  fmgeninl.h
  fmtimer.cpp  fmtimer.h
  headers.h  misc.h  opm.cpp  opm.h
  OpmEngineFmgen.h
  MODIFICATIONS.md  (このファイル)
```

内部インクルードを `"fmgen/xxx.h"` から `"xxx.h"` に変更。

### インクルードパスの調整

| ファイル | 変更前のインクルード | 変更後のインクルード |
|----------|---------------------|---------------------|
| `fmgen.h` | `"common/types.h"` | `"../types.h"` |
| `fmgen.cpp` | `"common/misc.h"`, `"fmgen/fmgen.h"`, `"fmgen/fmgeninl.h"` | `"headers.h"`, `"misc.h"`, `"fmgen.h"`, `"fmgeninl.h"` |
| `opm.cpp` | `"common/misc.h"`, `"fmgen/opm.h"`, `"fmgen/fmgeninl.h"` | `"headers.h"`, `"misc.h"`, `"opm.h"`, `"fmgeninl.h"` |

## 動作に関する改変

### 1. FM_SAMPLETYPE の変更（fmgen.h:14）

ハードコードされた `int32` を `MXDRVG_SAMPLETYPE` に変更し、
MP4M プロジェクト全体のサンプル型定義と整合させる。

```diff
-#define FM_SAMPLETYPE   int32
+#define FM_SAMPLETYPE   MXDRVG_SAMPLETYPE
```

`MXDRVG_SAMPLETYPE` は MP4M のヘッダで `int16_t` と定義されている。

### 2. GetChannelNote() の追加（opm.h:95）

各 OPM チャンネルのキーコード（ノート）を外部から取得できる公開メソッド。
mxdrvg_core.h の表示レイヤーから利用する。

```cpp
uint GetChannelNote(int ch)
{
    return (ch >= 0 && ch < 8) ? kc[ch] : 0;
}
```

### 3. HPF/LPF 後処理フィルタの追加（opm.cpp）

OPM ミックス後の出力にハイパス / ローパスフィルタチェーンを追加。
フィルタ状態変数は OPM クラス（opm.h）で宣言:

- `InpInpOpm[2]`, `InpOpm[2]` - フィルタ入出力
- `InpInpOpm_prev[2]`, `InpOpm_prev[2]` - 前サンプル状態
- `InpInpOpm_prev2[2]`, `InpOpm_prev2[2]` - 追加状態
- `OpmHpfInp[2]`, `OpmHpfInp_prev[2]`, `OpmHpfOut[2]` - HPF 状態

フィルタは `OPM::Mix()` 内で `filter` パラメータが true のときに動作。
`OPM::Reset()` でゼロ初期化される。

このフィルタは YM2151 のアナログ出力段をエミュレートする。

### 4. Clang 診断抑制（fmgeninl.h, fmgen.cpp）

`#pragma clang diagnostic push` / `#pragma clang diagnostic pop` を追加。
- `fmgeninl.h`: `-Wcomma` 警告を抑制
- `fmgen.cpp`: `-Wtautological-compare` 警告を抑制

### 5. SetSSGEC の簡略化（fmgeninl.h:138-149）

cisc オリジナル v1.27 には SSG タイプエンベロープの位相追跡ロジックが
あったが、本バージョン（v1.26 ベース）では位相依存の `ssg_phase_` 代入を
省略している。

```diff
 inline void Operator::SetSSGEC(uint ssgec)
 {
     if (ssgec & 8)
+        ssg_type_ = ssgec;
     else
+        ssg_type_ = 0;
-    {
-        ssg_type_ = ssgec;
-        switch (eg_phase_)
-        {
-        case attack:    ssg_phase_ = 0;  break;
-        case decay:     ssg_phase_ = 1;  break;
-        default:        ssg_phase_ = 2;  break;
-        }
-    }
-    else
-        ssg_type_ = 0;
-    param_changed_ = true;
 }
```

## 未改変のファイル

以下のファイルは cisc オリジナルから変更していない:
- `fmtimer.cpp`
- `fmtimer.h`

## ライセンス遵守

fmgen は (c) 1998-2003 cisc であり、以下の条件で使用している:

1. 全ソースファイルに元の著作権表記を保持。
2. プロジェクトルートの `LICENSE` ファイルに fmgen ライセンス条項の
   全文を記載（第5節）。
3. 本改変履歴をライセンス要件に従い提供。
4. 商用利用には cisc の事前承諾が必要。（MP4Mはオープンソースのため割愛。本人にメールしたが返信なし。）
