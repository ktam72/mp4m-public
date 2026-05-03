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
                    .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 15))
                    .foregroundColor(Color.mmdspCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                Spacer()
                if let dir = browserVM.currentDirectory {
                    Text(dir.path)
                        .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14))
                        .foregroundColor(Color.mmdspText.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.horizontal, 8)
                }
                Button { openFolder() } label: {
                    Text("[OPEN]").font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 15)).foregroundColor(Color.mmdspAmber)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .background(Color.mmdspBackground.opacity(0.8))
            Divider().background(Color.mmdspBorder)
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
            .background(Color.mmdspBackground)
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "フォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            browserVM.openDirectory(url)
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
                .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14))
                .foregroundColor(item.isDirectory ? Color.mmdspAmber : Color.mmdspText.opacity(0.5))
                .frame(width: 14)
            Text(item.displayName)
                .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 18))
                .foregroundColor(isPlaying ? Color.mmdspBright : Color.mmdspText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isPlaying {
                Text("▶").font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14)).foregroundColor(Color.mmdspBright)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? Color.mmdspSelected : Color.clear)
    }
}
