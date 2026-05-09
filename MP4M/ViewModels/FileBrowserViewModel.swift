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
                UserDefaults.standard.set(url, forKey: UserDefaultsKey.currentDirectory)
            }
        }
    }
    var fileItems: [FileItem] = []
    var selectedIndex: Int = -1
    var playingIndex: Int = -1

    /// コマンドライン引数で指定されたファイルのURL（再生用）
    var launchFileURL: URL?

    // MARK: - 初期化

    init() {
        print("[FileBrowserViewModel] init - START")
        print("[FileBrowserViewModel] MP4MApp.pendingPath: \(MP4MApp.pendingPath ?? "nil")")
        self.selectionStrategy = BrowserFileSelectionStrategy()

        if let pendingPath = MP4MApp.pendingPath {
            let url = URL(fileURLWithPath: pendingPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pendingPath, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                currentDirectory = url
                fileItems = FileItem.items(in: url)
                print("[FileBrowserViewModel] init - Directory: \(url.path)")
            } else {
                currentDirectory = url.deletingLastPathComponent()
                fileItems = FileItem.items(in: url.deletingLastPathComponent())
                launchFileURL = url
                print("[FileBrowserViewModel] init - File: \(url.path), launchFileURL set")
            }
        } else if let savedURL = UserDefaults.standard.url(forKey: UserDefaultsKey.currentDirectory) {
            currentDirectory = savedURL
            fileItems = FileItem.items(in: savedURL)
            print("[FileBrowserViewModel] init - Restored from UserDefaults: \(savedURL.path)")
        }
        print("[FileBrowserViewModel] init - END")
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
