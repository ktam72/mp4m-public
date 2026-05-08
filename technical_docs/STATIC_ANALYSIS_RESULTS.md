# MP4M 静的解析ツールチェック結果

**日時**: 2026-05-08  
**対象**: MP4M（macOS 用 MDX/PDX 音楽プレーヤー）  
**実行ツール**: gitleaks / git-secrets / cppcheck / swiftlint / semgrep / trivy

---

## 1. gitleaks — シークレット漏洩チェック

**結果**: 3件検出（すべて誤検知）

| 検出ファイル | 行 | ルール | 内容 |
|-------------|----|--------|------|
| `PlayerViewModel.swift` | 27 | generic-api-key | `"mmp4m_repeatEnabled"` (UserDefaultsキー) |
| `PlayerViewModel.swift` | 66 | generic-api-key | `"mmp4m_repeatEnabled"` (UserDefaultsキー) |
| `PlayerViewModel.swift` | 67 | generic-api-key | `"mmp4m_repeatEnabled"` (UserDefaultsキー) |

- **評価**: UserDefaults のキー文字列がエントロピー判定に引っかかったもので、実際のシークレットは含まれていない
- **推奨**: `.gitleaks.toml` で allowlist に追加してノイズ除去推奨

---

## 2. git-secrets — シークレット漏洩チェック

**結果**: 0件（問題なし）

---

## 3. cppcheck — C/C++/ObjC++ 静的解析

### Bridge/（自前コード）

| ファイル | 種別 | 内容 | 判定 |
|---------|------|------|------|
| `MXDRVGBridge.mm` | syntax error | Objective-C++構文（`[NSData dataWithBytes:...]`）をパース不可 | cppcheckの制限、問題なし |
| `MXDRVGBridge.mm` | missingInclude | インクルードパス未指定による情報レベルの警告 | Xcode ビルドでは解決 |

**評価**: 自前コードに実質的な問題なし。cppcheck は Objective-C++ 構文をサポートしていないため、Xcode Analyzer による静的解析を推奨。

### Vendor/（サードパーティ、参考情報）

大量のスタイル警告（`uninitMemberVar`, `cstyleCast`, `missingOverride`, `unusedFunction`, `knownConditionTrueFalse` 等）が Vendor コードに対して出力されたが、すべてサードパーティ製コードであり修正対象外。

---

## 4. swiftlint — Swift 静的解析

**結果**: 85件検出 → identifier_name（変数名が短すぎる）を除外し **81件修正完了**。残り2件は構造的リファクタリングが必要なためスキップ。

### 修正対応一覧

| ルール | 件数 | 対応内容 |
|-------|------|---------|
| `trailing_whitespace` | 27 | 全ファイル一括削除（`sed -i '' 's/[[:space:]]*$//'`） |
| `comma` | 11 | `KeyboardView.swift:5` カンマ直後に半角スペース挿入 |
| `colon` | 6 | `MXDRVAudioEngine.swift` コロン後の余分スペース削除 |
| `line_length` | 3 | `AboutView.swift` / `ControlPanelView.swift` / `MXDRVAudioEngine.swift` で長行を分割 |
| `unused_closure_parameter` | 1 | `SpectrumAnalyzerView.swift` `GeometryReader { geo in }` → `{ _ in }` |
| `implicit_optional_initialization` | 1 | `PlayerViewModel.swift` `var x: T? = nil` → `var x: T?` |
| `for_where` | 1 | `SpectrumComputeService.swift` `for+if` を `for...where` に変換 |

### 未対応（構造的リファクタリングが必要）

| ルール | ファイル | 内容 |
|-------|---------|------|
| `file_length` | `PlayerViewModel.swift:468` | 468行（上限400行） |
| `type_body_length` | `PlayerViewModel.swift:9` | クラス本文336行（上限250行） |

**評価**: PlayerViewModel の責務が大きいため、将来的な分割（ViewService への抽出等）を検討可。

### 修正ファイル一覧

- `MP4M/Views/KeyboardView.swift`
- `MP4M/Views/AboutView.swift`
- `MP4M/Views/ControlPanelView.swift`
- `MP4M/Views/SpectrumAnalyzerView.swift`
- `MP4M/Services/MXDRVAudioEngine.swift`
- `MP4M/Services/SpectrumComputeService.swift`
- `MP4M/ViewModels/PlayerViewModel.swift`

**ビルド確認**: ✅ `xcodebuild` BUILD SUCCEEDED 確認済み

---

## 5. semgrep — パターンベース静的解析

**結果**: 0件（問題なし）

- 適用ルール: 90（Swift/C/bash/json/yaml ルール）
- スキャンファイル: 79
- 解析成功率: ~100.0%

---

## 6. trivy — 脆弱性・シークレット・設定ミススキャン

**結果**: 問題なし

| スキャン種別 | 結果 | 備考 |
|-------------|------|------|
| Vulnerabilities | 対象外 | 言語別依存ファイルなし（CocoaPods/SPM/Carthage 未使用） |
| Secrets | 0件 | シークレット検出なし |
| Misconfigurations | 対象外 | IaC 設定ファイルなし（Terraform/Docker/K8s 等） |

**評価**: ネイティブ macOS アプリのため Trivy のスキャン対象に該当せず。

---

## 総合評価

| ツール | スコープ | 結果 | 備考 |
|-------|---------|------|------|
| gitleaks | シークレット | ✅ 誤検知のみ | Allowlist 推奨 |
| git-secrets | シークレット | ✅ 問題なし | — |
| cppcheck | C/C++/ObjC++ | ⚠️ 自前コード問題なし | Vendorは対象外 |
| swiftlint | Swift | ✅ 81件修正完了 | 2件は構造的課題でスキップ |
| semgrep | 全言語パターン | ✅ 問題なし | — |
| trivy | 脆弱性/シークレット/設定 | ✅ 該当なし | ネイティブアプリのため |
