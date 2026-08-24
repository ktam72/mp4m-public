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

    /// 並び替え基準（File = ファイル名順 / Title = MDX 内部タイトル順）
    var sortOrder: FileSortOrder = .file {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: UserDefaultsKey.fileSortOrder) }
    }
    /// 並び替え方向（true = 昇順）
    var sortAscending: Bool = true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: UserDefaultsKey.fileSortAscending) }
    }

    var selectedIndex: Int = -1
    var playingIndex: Int = -1

    /// コマンドライン引数で指定されたファイルのURL（再生用）
    var launchFileURL: URL?

    // MARK: - 初期化

    init() {
        print("[FileBrowserViewModel] init - START")
        print("[FileBrowserViewModel] MP4MApp.pendingPath: \(MP4MApp.pendingPath ?? "nil")")
        self.selectionStrategy = BrowserFileSelectionStrategy()

        if let savedSortRaw = UserDefaults.standard.string(forKey: UserDefaultsKey.fileSortOrder),
           let savedSort = FileSortOrder(rawValue: savedSortRaw) {
            sortOrder = savedSort
        }
        if UserDefaults.standard.object(forKey: UserDefaultsKey.fileSortAscending) != nil {
            sortAscending = UserDefaults.standard.bool(forKey: UserDefaultsKey.fileSortAscending)
        }

        if let pendingPath = MP4MApp.pendingPath {
            Log.debug("[BrowserVM] pendingPath=\(pendingPath)")
            let url = URL(fileURLWithPath: pendingPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pendingPath, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                currentDirectory = url
                fileItems = loadItems(in: url)
                Log.debug("[BrowserVM] Set currentDirectory to: \(url.path)")
            } else {
                currentDirectory = url.deletingLastPathComponent()
                fileItems = loadItems(in: url.deletingLastPathComponent())
                launchFileURL = url
                Log.debug("[BrowserVM] launchFileURL set to: \(url.path)")
            }
        } else if let savedURL = UserDefaults.standard.url(forKey: UserDefaultsKey.currentDirectory) {
            currentDirectory = savedURL
            fileItems = loadItems(in: savedURL)
            Log.debug("[BrowserVM] Restored saved directory: \(savedURL.path)")
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
        fileItems = loadItems(in: url)
        selectedIndex = 0
        playingIndex = -1
    }

    /// ディレクトリ移動
    func navigate(to item: FileItem) {
        guard item.isDirectory else { return }
        let previousDirectory = currentDirectory
        currentDirectory = item.url
        fileItems = loadItems(in: item.url)
        // 親へ戻った場合は、直前にいたフォルダを選択状態にする
        if let previous = previousDirectory,
           let index = fileItems.firstIndex(where: {
               $0.name != ".." && $0.url.standardizedFileURL == previous.standardizedFileURL
           }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        playingIndex = -1
    }

    /// 並び替え基準を設定する
    ///
    /// 同じ基準を再度指定した場合は昇順・降順を反転する。
    func setSortOrder(_ order: FileSortOrder) {
        if sortOrder == order {
            sortAscending.toggle()
        } else {
            sortOrder = order
            sortAscending = true
        }
        applySort()
    }

    /// 現在の並び替え設定で一覧を並べ替える（選択・再生位置は同じファイルを指し続ける）
    func applySort() {
        let selectedURL = (selectedIndex >= 0 && selectedIndex < fileItems.count)
            ? fileItems[selectedIndex].url
            : nil
        let currentPlayingURL = playingURL

        fileItems = FileItem.sorted(fileItems, sortOrder: sortOrder, ascending: sortAscending)

        selectedIndex = selectedURL.flatMap { url in
            fileItems.firstIndex { $0.url == url }
        } ?? -1
        playingIndex = currentPlayingURL.flatMap { url in
            playableFiles.firstIndex { $0.url == url }
        } ?? -1
    }

    /// 現在の並び替え設定でディレクトリを読み込む
    private func loadItems(in url: URL) -> [FileItem] {
        FileItem.items(in: url, sortOrder: sortOrder, ascending: sortAscending)
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
