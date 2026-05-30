import Foundation

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

    static func items(in directory: URL) -> [FileItem] {
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
        return result + dirs + files
    }


}
