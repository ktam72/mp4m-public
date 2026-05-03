# MP4M セキュリティ評価レポート
**日時**: 2026-05-04  
**対象**: MP4M（macOS 用 MDX/PDX 音楽プレーヤー）  
**評価方法**: 静的解析（Clang analyzer）+ コード審査 + OWASP Top 10 マッピング

---

## 実行環境の安全性 — ✅ 優秀

### App Sandbox 権限
**現状**: 最小権限で適切に構成
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-only</key><true/>
```
- ✅ ファイルアクセス：ユーザーが File Picker で選択したファイルのみ（read-only）
- ✅ ネットワーク権限：なし
- ✅ カメラ/マイク：なし
- ✅ 他プロセスアクセス：なし

**評価**: OWASP A1（Broken Access Control）対策は十分

---

## 静的解析結果 — ⚠️ 軽微な警告あり

### Clang Analyzer の検出

| ファイル | 警告内容 | 優先度 | 詳細 |
|---|---|---|---|
| `fmgen.cpp:222` | Dead Store | 低 | 変数 `v` が初期化直後に上書き（オーディオ計算ロジック、機能影響なし） |
| `fmgen.cpp:876,936` | Undefined Return | 低 | 条件分岐で変数 `r` 未初期化時の return（既知のデッドコード） |
| `MXDRVGBridge.mm:284,387-436` | Dead Stores | 低 | 未使用変数（pdxNameStart, fmCh, globalWork, keyOn, vol, len）- 削除可能 |

**評価**: セキュリティ脆弱性なし。コード品質向上の余地あり。

---

## コード審査 — ⚠️ 3つの脆弱性候補

### 1. 整数オーバーフロー / 型キャスト（優先度：高）

**場所**: `MXDRVGBridge.mm` — ファイルサイズ処理

**問題**: ファイルサイズが INT_MAX（2.1GB）を超えた場合、`int` へのキャストで符号反転
```objc
// Line 189, 195, 276 など
for (titleEndPos = 0; titleEndPos < (int)fileData.length; titleEndPos++) {
    // fileData.length が INT_MAX を超えると titleEndPos は負数に
}
```

**リスク**: 
- DoS（メモリ割り当て異常）
- バッファオーバーフロー（off-by-one）

**修正案**:
```objc
if (fileData.length > INT_MAX) {
    fputs("[ERROR] File too large (>2GB)\n", stderr);
    return nil;
}
```

---

### 2. バッファ境界チェック漏れ（優先度：高）

**場所**: `MXDRVGBridge.mm:103` — タイトル抽出ループ

**問題**: ファイル末尾が CR+LF で終わらない場合、`ptr[pos+1]` が bounds 外
```objc
for (pos = 0; pos < (int)data.length; pos++) {
    if (ptr[pos] == 0x0d && ptr[pos + 1] == 0x0a) break;  // pos+1 が未検証
}
```

**リスク**: バッファオーバーリード（機密情報漏洩、クラッシュ）

**修正案**:
```objc
for (pos = 0; pos < (int)data.length - 1; pos++) {  // -1 を追加
    if (ptr[pos] == 0x0d && ptr[pos + 1] == 0x0a) break;
}
```

---

### 3. LZX 展開サイズ上限なし（優先度：中）

**場所**: `lzx.cpp:56-62` — check() 関数

**問題**: `decompressed_size` に上限チェックがない
```cpp
unsigned int decompressed_size = 
    ((unsigned int)data[0x12] << 24) |  // ← 最大 4GB に
    ((unsigned int)data[0x13] << 16) |
    ((unsigned int)data[0x14] << 8) |
    data[0x15];
return decompressed_size;  // 制限なし
```

**リスク**: 
- DoS（メモリ枯渇）
- 悪意あるファイルで `malloc()` が巨大なサイズを要求

**修正案**:
```cpp
#define MAX_DECOMPRESSED_SIZE (64 * 1024 * 1024)  // 64MB上限
if (decompressed_size > MAX_DECOMPRESSED_SIZE) {
    return 0;  // 展開拒否
}
return decompressed_size;
```

---

### 4. PDX ファイル名抽出でヌル終端保証なし（優先度：中）

**場所**: `MXDRVGBridge.mm:204-220` — PDX 名前抽出ループ

**問題**: ファイル内にヌル終端がない場合、`fileData.length` まで走査
```objc
while (pdxNameEnd < (int)fileData.length && ptr[pdxNameEnd] != 0) {
    pdxNameEnd++;
}
// ここで pdxNameEnd == fileData.length の可能性あり

NSData* pdxName = [fileData subdataWithRange:NSMakeRange(mdxBodyStartPos, 
                                                         pdxNameEnd - mdxBodyStartPos)];
// 長さが正確な保証なし
```

**リスク**: 
- バッファオーバーリード（不正な PDX 名を読む）
- Shift-JIS / UTF-8 decode でクラッシュ

**修正案**:
```objc
int pdxNameMaxLen = (int)fileData.length - mdxBodyStartPos - 1;
if (pdxNameMaxLen <= 0) {
    strncpy(g_lastPDXFileName, "No PDX", sizeof(g_lastPDXFileName) - 1);
    pdxData = nil;
} else {
    // 名前抽出処理
}
```

---

## OWASP Top 10 マッピング

| OWASP# | リスク | MP4M の対応 | 評価 |
|---|---|---|---|
| A1: Broken Access Control | ユーザーが選択していないファイルへのアクセス | App Sandbox で保証 | ✅ OK |
| A2: Cryptographic Failures | 平文送信、弱い暗号 | N/A（ローカルアプリ） | ✅ OK |
| A3: Injection | MDX/PDX パーサーでのコード注入 | フォーマット仕様が限定的 | ⚠️ 要検証 |
| A4: Insecure Design | ファイルフォーマット仕様の不十分な検証 | **← 上記 4 項目がここ** | ⚠️ **高優先度** |
| A5: Security Misconfiguration | サンドボックス権限の過度な要求 | 権限は最小限 | ✅ OK |
| A6: Vulnerable Components | 依存ライブラリの脆弱性 | fmgen/gamdx は流用、定期検証必須 | ⚠️ 監視必要 |
| A7: Identification Failures | 認証の欠如 | N/A | ✅ OK |
| A8: Software/Data Integrity | ファイル完全性検証なし | MD5/SHA チェック未実装 | ⚠️ 検討項目 |
| A9: Logging/Monitoring | ログ内での機密情報漏洩 | `fprintf(stderr, ...)` が複数 | ⚠️ 本番環境対応必要 |
| A10: SSRF | サーバーサイドリクエスト偽造 | N/A（ネットワーク機能なし） | ✅ OK |

---

## 優先度別改善計画

### 🔴 **優先度：高** — 即時対応（セキュリティ脆弱性）

| # | 対策 | 労力 | リスク低減 |
|---|---|---|---|
| 1 | ファイルサイズ上限チェック（INT_MAX, 100MB） | 15分 | DoS 防止 |
| 2 | バッファ boundary チェック（CR+LF 探索） | 15分 | バッファオーバーリード 防止 |
| 3 | LZX 展開サイズ上限（64MB） | 10分 | DoS 防止 |
| 4 | PDX ファイル名抽出の長さ制限 | 20分 | バッファオーバーリード 防止 |

**合計労力**: 60分  
**テスト**: 不正フォーマットの MDX/PDX を用意して動作確認

---

### 🟡 **優先度：中** — 段階的対応（コード品質）

| # | 対策 | 内容 |
|---|---|---|
| 1 | Dead store 削除 | `MXDRVGBridge.mm` の未使用変数削除 |
| 2 | ログから機密情報削除 | 本番環境では `fprintf(stderr)` → `os_log` に変更 |
| 3 | 型安全性向上 | `int` → `size_t` への段階的移行 |

---

### 🟢 **優先度：低** — 将来の強化（ベストプラクティス）

| # | 対策 | 内容 |
|---|---|---|
| 1 | ファイル完全性検証 | MDX ヘッダーの Checksum / SHA256 検証 |
| 2 | エラーメッセージの一般化 | ログに詳細パス情報を含めない |
| 3 | ファジングテスト | 不正フォーマットの自動生成・テスト |

---

## 既知の良い実装

✅ **LZX バッファオーバーフロー防止**:
```cpp
if (out_pos >= out_end) return 0;  // Line 99, 141 — 確実なチェック
```

✅ **LZX 相対参照の範囲チェック**:
```cpp
if (out_pos + offset < data_start) return 0;  // Line 136 — 適切
```

✅ **Shift-JIS decode エラー時の fallback**:
```objc
NSString* title = [[NSString alloc] initWithData:titleData encoding:NSShiftJISStringEncoding];
if (!title) title = [[NSString alloc] initWithData:titleData encoding:NSUTF8StringEncoding];
return title ? title : @"(no title)";  // Line 111-114 — 安全
```

---

## 次のステップ

**今週**: 優先度高 4 項目の実装 + テスト  
**来週**: コード品質改善（Dead store 削除、ログ削除）  
**その後**: ファジングテスト、エラーケースの網羅的テスト

