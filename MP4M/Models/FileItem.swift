import Foundation

/// ファイルセレクターの並び替え基準
enum FileSortOrder: String, CaseIterable {
    /// ファイル名順
    case file  = "File"
    /// MDX 内部タイトル順
    case title = "Title"
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var title: String?    // MDX 内部タイトル (非同期でロード)

    var displayName: String {
        if let titleText = title, !titleText.isEmpty {
            return "\(name)    \(titleText)"
        }
        return name
    }

    static func items(in directory: URL,
                      sortOrder: FileSortOrder = .file,
                      ascending: Bool = true) -> [FileItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var dirs: [FileItem] = []
        var files: [FileItem] = []

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                dirs.append(FileItem(url: url, name: url.lastPathComponent, isDirectory: true))
            } else if ["mdx", "MDX"].contains(url.pathExtension) {
                var item = FileItem(url: url, name: url.lastPathComponent, isDirectory: false)
                // MDX タイトルを抽出（ファイル先頭から 0x0D 0x0A まで）
                if let data = try? Data(contentsOf: url, options: .alwaysMapped),
                   let title = MDXFileLoader.title(from: data) as String?,
                   !title.isEmpty, title != "(no title)" {
                    item.title = title
                }
                files.append(item)
            }
        }

        // 親ディレクトリへのナビゲーション項目 (..) を先頭に
        var result: [FileItem] = []
        if let parent = directory.deletingLastPathComponent() as URL?,
           parent != directory {
            result.append(FileItem(url: parent, name: "..", isDirectory: true))
        }
        return result + dirs + sortedFiles(files, sortOrder: sortOrder, ascending: ascending)
    }

    /// 既存の一覧を並び替える（`..`・ディレクトリの位置は変えず、ファイルのみ並び替え）
    ///
    /// 読み込み済みの MDX タイトルを保持したまま並び替えるため、ディレクトリの再読み込みは行わない。
    static func sorted(_ items: [FileItem],
                       sortOrder: FileSortOrder,
                       ascending: Bool) -> [FileItem] {
        let head = items.filter { $0.isDirectory }
        let files = items.filter { !$0.isDirectory }
        return head + sortedFiles(files, sortOrder: sortOrder, ascending: ascending)
    }

    /// ファイル項目のみを並び替える
    ///
    /// Title 順ではタイトル未取得のファイルを常に末尾へ回し、その中はファイル名順とする。
    private static func sortedFiles(_ files: [FileItem],
                                    sortOrder: FileSortOrder,
                                    ascending: Bool) -> [FileItem] {
        func compare(_ lhs: String, _ rhs: String) -> Bool {
            let result = lhs.localizedStandardCompare(rhs)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }

        switch sortOrder {
        case .file:
            return files.sorted { compare($0.name, $1.name) }
        case .title:
            let titled = files.filter { !($0.title ?? "").isEmpty }
            let untitled = files.filter { ($0.title ?? "").isEmpty }
            return titled.sorted { compare($0.title ?? "", $1.title ?? "") }
                + untitled.sorted { compare($0.name, $1.name) }
        }
    }


}
