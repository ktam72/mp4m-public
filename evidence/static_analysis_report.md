# MP4M 静的解析・脆弱性検査レポート

**日時:** 2026-05-13
**環境:** macOS 26.5, Xcode 17F42, arm64
**ツール:** SwiftLint 0.63.2, Xcode Static Analyzer, Semgrep 1.157.0, JPCERT C/C++ ルール

---

## 1. SwiftLint 静的コード解析

**対象:** Swift 23 ファイル
**結果:** 5 violations（すべて Warning、Error 0）

| # | ファイル | 行 | ルール | 内容 |
|---|---------|---|-------|------|
| 1 | `App/MP4MApp.swift` | 171 | identifier_name | 変数名 `i` は2～40文字であるべき |
| 2 | `App/MP4MApp.swift` | 202 | line_length | 125文字（上限120文字超過） |
| 3 | `ViewModels/PlayerViewModel.swift` | 508 | file_length | 508行（上限500行超過） |
| 4 | `Views/ContentView.swift` | 55 | line_length | 141文字（上限120文字超過） |
| 5 | `Views/ContentView.swift` | 144 | line_length | 129文字（上限120文字超過） |

### 評価
- 全て警告レベルで、重大な問題はなし
- `PlayerViewModel.swift` のファイル長超過はリファクタリング余地あり
- 行長超過は `.padding()` チェーンが主因

---

## 2. Xcode Static Analyzer（Clang 解析）

**結果:** ANALYZE SUCCEEDED（2 ファイルで警告あり）

### MXDRVGBridge.mm（6件）
| 行 | 種別 | 内容 |
|---|------|------|
| 21 | Dead store | 変数 `g_lastTitle` 未使用 |
| 277 | Dead store / Unused | 変数 `pdxNameMaxLen` 未使用 |
| 381 | Dead store / Unused | 変数 `pdxNameStart` 未使用 |
| 442,444 | 精度損失 | `unsigned long` → `ULONG`（unsigned int）暗黙変換 |
| 468,470 | 精度損失 | `unsigned long` → `ULONG`（unsigned int）暗黙変換 |
| 522 | Dead store / Unused | 変数 `fmCh` 未使用 |
| 556 | Dead store / Unused | 変数 `keyOn` 未使用 |
| 560 | Dead store / Unused | 変数 `vol` 未使用 |
| 561 | Dead store / Unused | 変数 `len` 未使用 |

### fmgen.cpp（3件）
| 行 | 種別 | 内容 |
|---|------|------|
| 222 | Dead store | 変数 `v` に代入後未使用 |
| 876 | **未初期化値返却** | 未初期化の `r` が return される可能性 |
| 936 | **未初期化値返却** | 未初期化の `r` が return される可能性 |

### MXDRVGBridge.h（3件）
| 行 | 種別 | 内容 |
|---|------|------|
| 13,14,22,23 | Nullability | ポインタに nullability 指定子がない |

### downsample.h（1件）
| 行 | 種別 | 内容 |
|---|------|------|
| 33 | Unused private field | `inpfirbuf_dummy` 未使用 |

### lowpass_44.dat / lowpass_48.dat
- `-Wmissing-braces` 多数（サブオブジェクト初期化の波括弧不足）—— 外部ベンダコードのため社会的に許容

### 評価
- **Critical:** fmgen.cpp の未初期化値返却（2箇所）は未定義動作の可能性あり
- 精度損失警告は arm64 では実害は少ないが、64bit 環境での移植性に注意
- デッドストアはデバッグコードの残存と推測

---

## 3. Semgrep 脆弱性スキャン

**実行モード:** `--config=auto`（57 ルール）
**対象:** 37 ファイル
**結果:** 0 findings（脆弱性なし）

| 言語 | ルール数 | 検出数 |
|------|---------|-------|
| Swift | 2 | 0 |
| C | 5 | 0 |
| JSON | 4 | 0 |
| マルチ言語 | 47 | 0 |

### 評価
- 標準ルールセットでは脆弱性を検出せず
- Swift ルールが2件のみと少ないため、網羅性には限界あり

---

## 4. JPCERT C/C++ セキュアコーディングルール検査

**対象:** `Vendor/gamdx/jni/fmgen/fmgen.cpp`
**結果:** 4 findings（すべて中リスク）

| ルール | 行 | リスク | 内容 |
|--------|---|-------|------|
| EXP33-C | 196 | 中 | 初期化されていない変数 `i` の可能性 |
| EXP33-C | 340 | 中 | 初期化されていない変数 `i` の可能性 |
| EXP33-C | 824 | 中 | 初期化されていない変数 `r` の可能性 |
| EXP33-C | 884 | 中 | 初期化されていない変数 `r` の可能性 |

**参考:** Xcode Static Analyzer も同箇所（876, 936行）で未初期化値返却を検出

---

## 5. セキュリティレビュー

### 5.1 機密情報
- APIキー、パスワード、トークン等のハードコード: **なし** ✅
- `UserDefaults` に保存する値はアプリ設定のみ（loopCount, autoMode, mutedChannels, currentDirectory）で機密情報なし ✅

### 5.2 エンタイトルメント
- Sandbox: 有効 ✅
- ファイルアクセス: `user-selected.read-only` のみ（必要最小限）✅
- ネットワーク権限: なし ✅

### 5.3 App Transport Security
- `NSAppTransportSecurity` 設定なし（ローカル音楽再生のみでネットワーク未使用）✅

### 5.4 Info.plist
- 最小限の設定のみ。過剰な権限要求なし ✅

### 5.5 ファイルアクセス
- `NSOpenPanel` 経由のユーザ選択のみ。
- Sandbox + read-only で安全。 ✅

---

## 6. 総評

| カテゴリ | ステータス |
|---------|-----------|
| SwiftLint | ⚠️ 5 warnings（軽微）|
| Xcode Static Analyzer | ⚠️ 多数の警告あり |
| Semgrep 脆弱性 | ✅ 0 findings |
| JPCERT C/C++ | ⚠️ 4 medium（未初期化変数）|
| 機密情報ハードコード | ✅ なし |
| エンタイトルメント | ✅ 適切 |
| ネットワークセキュリティ | ✅ 問題なし |

### 対応推奨事項（優先度順）

1. **🔴 [高] fmgen.cpp の未初期化値返却**（EXP33-C）
   - `fmgen.cpp:876,936` の `return r;` で未初期化値が返る可能性。条件分岐がすべてのパスをカバーしているか確認し、初期化または防御的コードを追加。

2. **🟡 [中] デッドストアの削除**
   - `MXDRVGBridge.mm` および `fmgen.cpp` の不要変数代入は可読性低下と誤解釈リスクのため削除推奨。

3. **🟡 [中] 暗黙の整数精度損失**
   - `unsigned long` → `ULONG` 変換は arm64 では安全だが、将来的な移植性のため明示的キャスト追加を推奨。

4. **🟢 [低] SwiftLint 警告対応**
   - 変数名 `i` → 意味のある名前に変更
   - 長行の分割
   - `PlayerViewModel.swift` のファイル分割検討

5. **🟢 [低] Nullability 指定子追加**
   - `MXDRVGBridge.h` のポインタ引数に `_Nonnull` / `_Nullable` を追加
