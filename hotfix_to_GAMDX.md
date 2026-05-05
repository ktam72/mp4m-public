# GAMDX への修正履歴

このドキュメントは、MP4M プロジェクトが GAMDX フォルダ配下のソースコードに加えた修正をすべて記録しています。

---

## 1. タイマーオーバーフロー修正（致命的バグ）

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/timer.h`, `timer.cpp`, `mxdrvg_core.h`

### 問題
- `timer_a_count_` が `uint16_t` の場合、Timer A 周期（典型値 16384 µs）をストアするとオーバーフロー → 常に 0
- `timer_b_count_` が `uint8_t` の場合、Timer B 周期（65536 µs）をストアすると 0 に → `GetNextEventTime()` が常に 0 を返す
- 結果：GetPCM ループで毎反復 `OPMINTFUNC` を呼び出す → **再生速度が 3〜4 倍に加速**

### 修正内容
```cpp
// timer.h
- static uint16_t timer_a_count_;     // ❌ オーバーフロー
- static uint8_t timer_b_count_;      // ❌ オーバーフロー
+ static uint32_t timer_a_count_;     // ✅ 十分な幅
+ static uint32_t timer_b_count_;     // ✅ 十分な幅
```

```cpp
// timer.cpp - Advance() 比較ロジック
- if (timer_count_ <= 0) {            // ❌ 符号なしでは never true
+ if (timer_count_ <= microseconds) { // ✅ 正しいアンダーフロー検出
```

### 影響
- OPM タイマーの周期が正確に計測される
- OPMINTFUNC コール頻度が正規化（毎フレームではなく必要時のみ）
- 再生速度が正常化

---

## 2. OPMINTFUNC 二重呼び出し修正

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
`MXDRVG_GetPCM()` 内で `OPMINTFUNC` が 2 回呼ばれていた

### 修正内容
```cpp
// mxdrvg_core.h - GetPCM ループ
  for (...)
  {
-   OPMINTFUNC();  // ❌ 不要な第 1 回呼び出し
    if (fmgen.getNextEventTime() > ...) {
        OPMINTFUNC(); // ✅ 必要な呼び出しのみ
    }
  }
```

### 影響
- GetPCM のループ効率改善
- FM 音声処理の重複排除

---

## 3. MXDRVG_GetPCM 内のデバッグログ全削除

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
GetPCM ループのホットパスに大量の `printf` が残存（毎フレーム呼び出し）

### 修正内容
```cpp
// 削除対象
- fprintf(..., "[PCM_DETAIL] ...");  // GetPCM ループ内で毎フレーム
- fprintf(..., "[FM_RAW] ...");      // OPM_SUB 内で大量出力
- fprintf(..., "[PCM_RAW] ...");
```

### 影響
- オーディオスレッド（IOThread）の負荷軽減
- ログ出力による音声スレッド遅延排除

---

## 4. TotalVolume 初期値修正

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
TotalVolume が 0 で初期化されていた → 無音問題

### 修正内容
```cpp
// mxdrvg.h - Start()
- int TotalVolume = 0;       // ❌ 無音
+ int TotalVolume = 256;     // ✅ 50% 音量で初期化
```

### 影響
- オーディオエンジン開始時に正常な音量で再生開始

---

## 5. PDX ファイル自動ロード（大文字小文字対応）

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h` (準備), `MP4M/Bridge/MXDRVGBridge.mm` (実装)

### 問題
MDX ヘッダーで指定された PDX ファイル名が見つからない → PCM パート無音

### 修正内容
```cpp
// MXDRVGBridge.mm - loadMDXFile:
- pdxData = nil;  // ❌ PDX ファイルを探さない
+ pdxData = findPDXFile(pdxFileName, mdxDir);  // ✅ 同ディレクトリで大文字小文字を区別せず検索
```

`findPDXFile()` の実装：
- ディレクトリ内の全ファイルを列挙
- 指定されたファイル名と lowercaseString で比較
- `.pdx` 拡張子がない場合は自動補完
- パストラバーサル対策（`/`, `..`, `\` チェック）

### 影響
- PDX ファイルが自動認識される
- Windows/macOS のファイルシステム差異（大文字小文字）を吸収
- PCM パートが正常に再生

---

## 6. L_0F() シーケンスリセット追加

**commit**: 841c811  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
`MXDRVG_SetData()` の直後に `MXDRVG_PlayAt()` を呼ぶと、シーケンスが冒頭で正しく再生されない場合がある

### 修正内容
```cpp
// mxdrvg_core.h - SetData() 終了直前
+ L_0F();  // ✅ シーケンスポインタをリセット
```

### 影響
- MDX ファイルロード後の再生開始が確実になる

---

## 7. FM チャンネル PAN ビット抽出修正

**commit**: 1016bba  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
FM チャンネルの PAN 取得が YM2151 仕様（bit 6-7）ではなく下位ビット（bit 0-1）を参照

### 修正内容
```cpp
// mxdrvg_core.h - OPM_GetChannelStates()
- int pan = (S001c & 0x03);        // ❌ bit 0-1（誤り）
+ int pan = (S001c >> 6) & 0x03;   // ✅ bit 6-7（YM2151 仕様）
```

マッピング：
```
(bit6,bit7) = 0b01 → pan=0 (Left)
(bit6,bit7) = 0b10 → pan=2 (Right)
(bit6,bit7) = 0b11 → pan=3 (LR/Stereo)
(bit6,bit7) = 0b00 → pan=1 (Center)
```

### 影響
- FM チャンネルのパン表示が正確に

---

## 8. PCM チャンネル PAN 動的取得

**commit**: 244a58b  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`, `x68pcm8.h`

### 問題
PCM チャンネルの PAN が静的な固定値

### 修正内容
```cpp
// x68pcm8.h - GetChannelMode() 関数追加
int GetChannelMode(int ch) {
    return pcmCh[ch].Mode & 0x03;  // Mode フィールドから PAN 抽出
}
```

PCM8 パン値マッピング：
```
Mode & 0x03:
0x01 → pan=0 (Left)
0x02 → pan=2 (Right)
0x03 → pan=3 (Stereo)
その他 → pan=1 (Center)
```

### 影響
- PCM チャンネルのパンが演奏時に動的に変化
- ステレオ PCM サンプルのパン情報を反映

---

## 9. PCM チャンネル有効性判定修正

**commit**: 03c0b07, 2821383  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`, `x68pcm8.h`

### 問題
PCM チャンネルが使用中かどうかの判定が不正確

### 修正内容
```cpp
// mxdrvg_core.h - MXDRVG_WORK_PCM アクセス
- bool isActive = (flags & 0x04) != 0;  // ❌ 不正な判定
+ bool isActive = (S0000 != NULL) && (S0000 != 0);  // ✅ サンプルポインタで判定
  // + keyOn フラグも確認（S0016 bit 3）
```

### 影響
- 未使用 PCM チャンネルが誤検出されない
- スペアナ・レベルメーター表示が正確化

---

## 10. チャンネル状態の velocity フィールド修正

**commit**: b1a84ed  
**file**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`

### 問題
`velocity` フィールドが微小値（4-7/127）で、レベルメーター表示がほぼ0になる

### 修正内容
```cpp
// OPM_GetChannelStates()
- state.velocity = (velocity_register & 0x7F);  // ❌ 微小値
+ state.velocity = keyOn ? 100 : 0;             // ✅ keyOn フラグに基づく固定値
```

### 影響
- レベルメーターが視認可能な高さで表示される
- キー発音状態が明確に可視化

---

## 11. デバッグログの段階的削除

**commits**: 0277e4d, 049ead4, 841c811  
**files**: `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h`, `timer.cpp`, その他

### 削除対象
- `[OPM]` ログ（オペレータパラメータ設定）
- `[OPMINT]` ログ（タイマー割り込み）
- `[L_OPMINT]` ログ（割り込み関数）
- `[MixWrapper]` ログ
- `[PCM_DETAIL]` ログ
- その他オーディオスレッドのホットパス printf

### 影響
- オーディオスレッド負荷軽減
- ログ出力による音声スレッド遅延排除

---

## 12. 未使用ファイル削除

**commit**: 444ac12  
**file**: `Vendor/gamdx/jni/`

### 削除対象
- `jniwrap/` — JNI ラッパー（Android 不要）
- `mxdrvg.cpp` — MXDRVG 古い実装
- `lzx042/` — LZX 旧デコンプレッサ（オリジナル実装に置き換え）

### 理由
- macOS SwiftUI のみ対応のため JNI 不要
- LZX は Microsoft 仕様準拠オリジナル実装に統一
- ソースコード規模削減・メンテナンス簡素化

---

## 修正の歴史的背景

### Phase 1: GAMDX 統合（初期～bc59dcc）
- GAMDX をフォルダ丸ごと導入
- fmgen OPM エミュレータで構成

### Phase 2: クリティカルバグ修正（841c811）
- **タイマーオーバーフロー** → 再生速度 3-4 倍
- OPMINTFUNC 二重呼び出し
- デバッグ printf のホットパス問題
- PDX 自動ロード

### Phase 3: チャンネル表示改善（244a58b～1016bba）
- PAN ビット抽出の誤りを修正
- PCM チャンネル PAN を動的取得
- FM チャンネルの bit6/bit7 抽出修正
- チャンネル有効性判定の精密化

### Phase 4: クリーンアップ（444ac12）
- 未使用ファイルと JNI 削除
- ソースコード規模削減

---

## セキュリティ対策

以下のセキュリティチェックも GAMDX コード内に追加：

1. **ファイルサイズ検証** — MDX/PDX の最小/最大サイズチェック
2. **LZX 展開サイズ制限** — 爆発的展開（zip bomb 相当）防止（1MB 上限）
3. **ヘッダー境界チェック** — Shift-JIS タイトル抽出時のバッファオーバーラン防止
4. **パストラバーサル防止** — PDX ファイル名の `..`, `/`, `\` チェック
5. **シーケンスポインタ範囲チェック** — 不正なシーケンスアドレスへのアクセス防止
6. **再生ループ上限** — 無限ループ防止（1000 万反復上限）

---

## 参考リンク

- **GAMDX 公式リポジトリ**: https://gorry.haun.org/android/gamdx/
- **Microsoft LZX**: LZ77 ベース圧縮フォーマット

---

**最終更新**: 2026-05-06  
**ドキュメント作成**: Claude Haiku 4.5
