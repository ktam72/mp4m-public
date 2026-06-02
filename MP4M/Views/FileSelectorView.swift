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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(browserVM.fileItems.enumerated()), id: \.element.id) { idx, item in
                        FileRowView(
                            item: item,
                            isSelected: idx == browserVM.selectedIndex,
                            isPlaying: item.url == browserVM.playingURL
                        )
                        .onTapGesture(count: 2) { doubleTap(item: item) }
                        .onTapGesture(count: 1) { browserVM.selectItem(at: idx) }
                    }
                }
            }
            .background(Color.mp4mBackground)
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

    var body: some View {
        HStack(spacing: 6) {
            Text(item.isDirectory ? "►" : "♪")
                .font(.mp4mTiny)
                .foregroundColor(item.isDirectory ? Color.mp4mAmber : Color.mp4mText.opacity(0.5))
                .frame(width: 14)
            Text(item.displayName)
                .font(.mp4mText)
                .foregroundColor(isPlaying ? Color.mp4mBright : Color.mp4mText)
                .shadow(color: isPlaying ? Color.mp4mBright.opacity(0.6) : .clear, radius: isPlaying ? 12 : 0)
                .shadow(color: isPlaying ? Color.mp4mBright.opacity(0.3) : .clear, radius: isPlaying ? 24 : 0)
                .lineLimit(1)
                .truncationMode(.tail)
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
}
