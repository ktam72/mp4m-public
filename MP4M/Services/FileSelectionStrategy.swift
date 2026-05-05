import Foundation
import AppKit

/// ファイル/フォルダ選択ストラテジープロトコル
protocol FileSelectionStrategy {
    /// フォルダを選択し、選択されたURLを返す（キャンセル時はnil）
    func selectDirectory() async -> URL?
}

/// デフォルトのブラウザフォルダ選択ストラテジー（NSOpenPanel使用）
final class BrowserFileSelectionStrategy: FileSelectionStrategy {
    func selectDirectory() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "フォルダを選択"
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}
