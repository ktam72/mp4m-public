import Foundation
import Observation

/// ファイルブラウザ状態を管理する ViewModel
@MainActor
@Observable
final class FileBrowserViewModel {
    // MARK: - 策略属性
    var selectionStrategy: FileSelectionStrategy = BrowserFileSelectionStrategy()
    // MARK: - 表示状態

    var currentDirectory: URL? {
        didSet {
            if let url = currentDirectory {
                UserDefaults.standard.set(url, forKey: "mp4m_currentDirectory")
            }
        }
    }
    var fileItems: [FileItem] = []
    var selectedIndex: Int = -1
    var playingIndex: Int = -1

    // MARK: - 初期化

    init() {
        // 選択ストラテジーを初期化
        self.selectionStrategy = BrowserFileSelectionStrategy()
        
        // UserDefaults から設定を復帰
        if let savedURL = UserDefaults.standard.url(forKey: "mp4m_currentDirectory") {
            currentDirectory = savedURL
            fileItems = FileItem.items(in: savedURL)
        }
    }

    // MARK: - 公開 API

    /// 再生可能なファイル（ディレクトリを除外）
    var playableFiles: [FileItem] {
        fileItems.filter { !$0.isDirectory }
    }

    /// ディレクトリを開く
    func openDirectory(_ url: URL) {
        currentDirectory = url
        fileItems = FileItem.items(in: url)
        selectedIndex = 0
        playingIndex = -1
    }

    /// ディレクトリ移動
    func navigate(to item: FileItem) {
        guard item.isDirectory else { return }
        currentDirectory = item.url
        fileItems = FileItem.items(in: item.url)
        selectedIndex = 0
        playingIndex = -1
    }

    /// ファイル選択
    func selectItem(at index: Int) {
        selectedIndex = index
    }

    /// 現在再生中の URL を取得
    var playingURL: URL? {
        guard playingIndex >= 0, playingIndex < playableFiles.count else { return nil }
        return playableFiles[playingIndex].url
    }

    /// 選択アイテムがディレクトリかどうか
    func isDirectorySelected(at index: Int) -> Bool {
        guard index >= 0, index < fileItems.count else { return false }
        return fileItems[index].isDirectory
    }
}
