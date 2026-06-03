import Foundation
import SwiftUI

/// MP4M アプリケーション全体で使用する統一エラー型
enum MP4MError: LocalizedError, Identifiable {
    case pdxLoadFailed(String)
    case mdxLoadFailed(String)
    case audioEngineFailed(String)
    case fileAccessDenied(String)

    var errorDescription: String? {
        switch self {
        case .pdxLoadFailed(let reason):
            return "PDXファイルの読み込みに失敗しました: \(reason)"
        case .mdxLoadFailed(let reason):
            return "MDXファイルの読み込みに失敗しました: \(reason)"
        case .audioEngineFailed(let reason):
            return "オーディオエンジンでエラーが発生しました: \(reason)"
        case .fileAccessDenied(let reason):
            return "ファイルへのアクセスが拒否されました: \(reason)"
        }
    }

    var id: String {
        switch self {
        case .pdxLoadFailed(let reason): return "pdxLoadFailed-\(reason)"
        case .mdxLoadFailed(let reason): return "mdxLoadFailed-\(reason)"
        case .audioEngineFailed(let reason): return "audioEngineFailed-\(reason)"
        case .fileAccessDenied(let reason): return "fileAccessDenied-\(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pdxLoadFailed:
            return "PDXファイルが破損していないか、正しいディレクトリにあるか確認してください。"
        case .mdxLoadFailed:
            return "MDXファイルが破損していないか、対応形式か確認してください。"
        case .audioEngineFailed:
            return "アプリを再起動するか、別のファイルを試してください。"
        case .fileAccessDenied:
            return "ファイル選択ダイアログから再度ファイルを選択してください。"
        }
    }
}
