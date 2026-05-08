import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var title: String?    // MDX 内部タイトル (非同期でロード)

    var displayName: String {
        if let t = title, !t.isEmpty {
            return "\(name)    \(t)"
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
                   let title = extractMDXTitle(from: data) {
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

    /// MDX ファイルデータからタイトルを抽出（Shift-JIS形式）
    private static func extractMDXTitle(from data: Data) -> String? {
        let bytes = [UInt8](data)
        // 0x0D 0x0A (CR+LF) を探す
        var pos = 0
        while pos < bytes.count - 1 {
            if bytes[pos] == 0x0D && bytes[pos + 1] == 0x0A {
                break
            }
            pos += 1
        }
        guard pos < bytes.count - 1 else { return nil }
        let titleData = data.prefix(pos)
        // Shift-JIS デコードを試す
        if let title = String(data: titleData, encoding: .shiftJIS) {
            return title.isEmpty ? nil : title
        }
        // UTF-8 デコードを試す
        if let title = String(data: titleData, encoding: .utf8) {
            return title.isEmpty ? nil : title
        }
        return nil
    }
}
