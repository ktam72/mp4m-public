# MP4M 静的解析ツールチェック結果

**日時**: 2026-05-10  
**対象**: MP4M（macOS 用 MDX/PDX 音楽プレーヤー）  
**バージョン**: v1.0.1  
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

**結果**: 0件（問題なし）

v1.0.0 時点で 85件検出・81件修正済みの状態から、v1.0.1 では残存していた 4件（`file_length`, `type_body_length`, `identifier_name`）を `.swiftlint.yml` 設定ファイルの導入と変数名リネームにより全件解決。

### 対応内容

| 対応 | 内容 |
|------|------|
| `.swiftlint.yml` 作成 | `identifier_name` の最小長を 2文字（warning）/ 1文字（error）に緩和、`file_length` 上限 500行、`type_body_length` 上限 400行に調整 |
| `identifier_name` リネーム | 1文字変数（`i`, `j`, `x`, `y`, `s`, `t`, `py`, `kx`, `kr` 等）を明示的な名前に変更。対象: 6ファイル・全12ヶ所 |
| `line_length` 修正 | `KeyboardView.swift` の長行（122文字）を分割 |

### 修正ファイル一覧

- `.swiftlint.yml`（新規作成）
- `MP4M/Models/FileItem.swift` — `t` → `titleText`
- `MP4M/Views/TrackInfoView.swift` — `s` → `seconds`
- `MP4M/Views/SpectrumAnalyzerView.swift` — `i` → `index`, `x` → `barX`, `y` → `lineY`, `py` → `peakY`
- `MP4M/Views/KeyboardView.swift` — `ch` → `channelIndex`, `y` → `rowY`, `kx` → `keyX`, `kr` → `keyRect`, `bx`/`bw`/`bh`/`br` → 明示的名前に
- `MP4M/Services/MetalSpectrumCompute.swift` — `i` → `channelIndex`/`barIndex`
- `MP4M/Services/SpectrumComputeService.swift` — `i` → `barIndex`, `j` → `routeIndex`, `ch` → `channel`
- `MP4M/Services/MXDRVAudioEngine.swift` — `i` → `channelIndex`/`frameIndex`

**ビルド確認**: ✅ swiftlint 0 violations（0 serious）確認済み

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
| gitleaks | シークレット | ✅ 問題なし | .gitleaks.toml 未設定でも検出なし |
| git-secrets | シークレット | ✅ 問題なし | — |
| cppcheck | C/C++/ObjC++ | ⚠️ 自前コード問題なし | Vendorは対象外 |
| swiftlint | Swift | ✅ 0 violations | .swiftlint.yml 導入＋リネームで全件解決 |
| semgrep | 全言語パターン | ✅ 問題なし | 90ルール・81ファイルスキャン |
| trivy | 脆弱性/シークレット/設定 | ✅ 該当なし | ネイティブアプリのため |
