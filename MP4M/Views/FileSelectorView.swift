import SwiftUI
import AppKit

/// ファイルセレクター: MDX ファイルのディレクトリブラウザ
struct FileSelectorView: View {
    let browserVM: FileBrowserViewModel
    let playerVM: PlayerViewModel?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("FILE SELECTOR")
                    .font(.mp4mSmall)
                    .foregroundColor(Color.mp4mCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                Spacer()
                if let dir = browserVM.currentDirectory {
                    Text(dir.path)
                        .font(.mp4mTiny)
                        .foregroundColor(Color.mp4mText.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.horizontal, 8)
                        .textSelection(.enabled)
                        .help(dir.path)
                        .contextMenu {
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(dir.path, forType: .string)
                            }
                        }
                }
                Button { openFolder() } label: {
                    Text("[OPEN]").font(.mp4mSmall).foregroundColor(Color.mp4mAmber)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .background(Color.mp4mBackground.opacity(0.8))
            Divider().background(Color.mp4mBorder)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(browserVM.fileItems.enumerated()), id: \.element.id) { idx, item in
                            FileRowView(
                                item: item,
                                isSelected: idx == browserVM.selectedIndex,
                                isPlaying: item.url == browserVM.playingURL,
                                nameColumnWidth: nameColumnWidth
                            )
                            .onTapGesture(count: 2) { doubleTap(item: item) }
                            .onTapGesture(count: 1) { browserVM.selectItem(at: idx) }
                            .contextMenu {
                                Button("Copy Path") { copyPath(of: item) }
                            }
                        }
                    }
                }
                .background(Color.mp4mBackground)
                // ディレクトリ移動後、選択項目を表示エリアの先頭に合わせる
                .onChange(of: browserVM.currentDirectory) {
                    scrollToSelection(proxy)
                }
            }
        }
    }

    /// ファイル名カラムの幅（タイトルの先頭を縦に揃えるため、一覧内の最長ファイル名に合わせる）
    private var nameColumnWidth: CGFloat {
        let longest = browserVM.fileItems
            .filter { !$0.isDirectory }
            .map(\.name.count)
            .max() ?? 0
        guard longest > 0 else { return 0 }
        // 名前とタイトルの間に 2 文字分の余白を確保する
        return min(CGFloat(longest + 2) * Self.monoAdvance, Self.maxNameColumnWidth)
    }

    /// 等幅フォント 1 文字分の送り幅
    private static let monoAdvance: CGFloat = {
        let font = NSFont(name: "MonaspaceNeon-Regular", size: 18) ?? .monospacedSystemFont(ofSize: 18, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()

    /// ファイル名カラムの上限幅（極端に長い名前でタイトルが押し出されるのを防ぐ）
    private static let maxNameColumnWidth: CGFloat = 420

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let index = browserVM.selectedIndex
        guard index >= 0, index < browserVM.fileItems.count else { return }
        let id = browserVM.fileItems[index].id
        // LazyVStack の再構築後にスクロールさせるため次のループへ回す
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func doubleTap(item: FileItem) {
        if item.isDirectory {
            browserVM.navigate(to: item)
        } else {
            guard let playerVM else { return }
            if let idx = browserVM.fileItems.filter({ !$0.isDirectory })
                .firstIndex(where: { $0.id == item.id }) {
                browserVM.playingIndex = idx
            }
            Task {
                await playerVM.load(url: item.url)
                playerVM.play()
            }
        }
    }

    /// 項目のフルパスをクリップボードにコピーする
    private func copyPath(of item: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    private func openFolder() {
        Task {
            if let url = await browserVM.selectionStrategy.selectDirectory() {
                browserVM.openDirectory(url)
            }
        }
    }
}

private struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let isPlaying: Bool
    /// ファイル名カラムの幅（0 ならタイトル列なし）
    let nameColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(item.isDirectory ? "►" : "♪")
                .font(.mp4mTiny)
                .foregroundColor(item.isDirectory ? Color.mp4mAmber : Color.mp4mText.opacity(0.5))
                .frame(width: 14)
            HStack(spacing: 0) {
                // ファイル名は固定幅カラムに置き、タイトルの先頭を縦に揃える
                rowText(item.name)
                    .frame(
                        width: nameColumnWidth > 0 && !item.isDirectory ? nameColumnWidth : nil,
                        alignment: .leading
                    )
                if let title = item.title, !title.isEmpty {
                    rowText(title)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPlaying {
                Text("▶")
                    .font(.mp4mTiny)
                    .foregroundColor(Color.mp4mBright)
                    .shadow(color: Color.mp4mBright.opacity(0.6), radius: 12)
                    .shadow(color: Color.mp4mBright.opacity(0.3), radius: 24)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? Color.mp4mSelected : Color.clear)
    }

    /// 行内テキストの共通スタイル（再生中はグロー）
    private func rowText(_ text: String) -> some View {
        Text(text)
            .font(.mp4mText)
            .foregroundColor(isPlaying ? Color.mp4mBright : Color.mp4mText)
            .shadow(color: isPlaying ? Color.mp4mBright.opacity(0.6) : .clear, radius: isPlaying ? 12 : 0)
            .shadow(color: isPlaying ? Color.mp4mBright.opacity(0.3) : .clear, radius: isPlaying ? 24 : 0)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
