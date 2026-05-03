import SwiftUI
#if os(macOS)
import AppKit
#endif

/// ファイルセレクター: MDX ファイルのディレクトリブラウザ
struct FileSelectorView: View {
    let browserVM: FileBrowserViewModel
    let playerVM: PlayerViewModel?
    #if os(iOS)
    @State private var isImporting = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("FILE SELECTOR")
                    .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 15))
                    .foregroundColor(Color.mp4mCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                Spacer()
                if let dir = browserVM.currentDirectory {
                    Text(dir.path)
                        .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14))
                        .foregroundColor(Color.mp4mText.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.horizontal, 8)
                }
                Button { openFolder() } label: {
                    Text("[OPEN]").font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 15)).foregroundColor(Color.mp4mAmber)
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
        #if os(iOS)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    browserVM.openDirectory(url)
                case .failure(let error):
                    print("フォルダ選択エラー: \(error)")
                }
            }
        )
        #endif
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
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "フォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            browserVM.openDirectory(url)
        }
        #else
        isImporting = true
        #endif
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
                .foregroundColor(item.isDirectory ? Color.mp4mAmber : Color.mp4mText.opacity(0.5))
                .frame(width: 14)
            Text(item.displayName)
                .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 18))
                .foregroundColor(isPlaying ? Color.mp4mBright : Color.mp4mText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isPlaying {
                Text("▶").font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14)).foregroundColor(Color.mp4mBright)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? Color.mp4mSelected : Color.clear)
    }
}
