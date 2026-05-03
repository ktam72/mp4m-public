import Foundation
import Observation

/// ファイルブラウザ状態を管理する ViewModel
@MainActor
@Observable
final class FileBrowserViewModel {
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
        // UserDefaults から設定を復帰
        if let savedURL = UserDefaults.standard.url(forKey: "mp4m_currentDirectory") {
            currentDirectory = savedURL
            fileItems = FileItem.items(in: savedURL)
        }
    }

    // MARK: - 公開 API

    /// ディレクトリを開く
    func openDirectory(_ url: URL) {
        currentDirectory = url
        fileItems = FileItem.items(in: url)
        selectedIndex = 0
    }

    /// ディレクトリ移動
    func navigate(to item: FileItem) {
        guard item.isDirectory else { return }
        currentDirectory = item.url
        fileItems = FileItem.items(in: item.url)
        selectedIndex = 0
    }

    /// ファイル選択
    func selectItem(at index: Int) {
        selectedIndex = index
    }

    /// 現在再生中の URL を取得
    var playingURL: URL? {
        let files = fileItems.filter { !$0.isDirectory }
        guard playingIndex >= 0, playingIndex < files.count else { return nil }
        return files[playingIndex].url
    }

    /// 選択アイテムがディレクトリかどうか
    func isDirectorySelected(at index: Int) -> Bool {
        guard index >= 0, index < fileItems.count else { return false }
        return fileItems[index].isDirectory
    }
}
