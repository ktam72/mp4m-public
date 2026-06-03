import Foundation
import AppKit

/// ファイル/フォルダ選択ストラテジーのプロトコル
/// 異なる選択UI（ブラウザ、ドラッグ＆ドロップ等）への拡張を容易にする
protocol FileSelectionStrategy {
    /// フォルダを選択し、選択されたURLを返す（キャンセル時はnil）
    /// - Returns: 選択されたフォルダのURL、キャンセル時はnil
    /// - Note: メインスレッドで実行する必要がある（NSOpenPanel等のため）
    func selectDirectory() async -> URL?
}

/// デフォルトのブラウザフォルダ選択ストラテジー（NSOpenPanel使用）
/// 既存のFileSelectorViewのフォルダ選択ロジックをラップした実装
final class BrowserFileSelectionStrategy: FileSelectionStrategy {
    func selectDirectory() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "フォルダを選択"
            panel.directoryURL = URL(fileURLWithPath: "/tmp")
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}
