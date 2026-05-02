import SwiftUI

/// コントロールパネル: 再生操作ボタン + オートモード
struct ControlPanelView: View {
    let viewModel: PlayerViewModel?
    let browserVM: FileBrowserViewModel?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                PanelButton(label: "◀◀", action: playPrev)
                PanelButton(label: playPauseLabel, action: { viewModel?.togglePlay() })
                PanelButton(label: "■", action: { viewModel?.stop() })
                PanelButton(label: "▶▶", action: playNext)
            }
            Divider().background(Color.mmdspBorder)
            HStack(spacing: 4) {
                Text("LOOP:").font(.mmdspSmall).foregroundColor(Color.mmdspText.opacity(0.7))
                Button { viewModel?.setLoopCount((viewModel?.loopCount ?? 2) - 1) } label: {
                    Text("-").font(.mmdspMono).foregroundColor(Color.mmdspAmber)
                }
                .buttonStyle(.plain)
                Text(viewModel?.loopCount == 0 ? "∞" : "\(viewModel?.loopCount ?? 2)")
                    .font(.mmdspMono).foregroundColor(Color.mmdspBright).frame(width: 20)
                Button { viewModel?.setLoopCount((viewModel?.loopCount ?? 2) + 1) } label: {
                    Text("+").font(.mmdspMono).foregroundColor(Color.mmdspAmber)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            Divider().background(Color.mmdspBorder)
            HStack(spacing: 6) {
                ForEach(AutoMode.allCases, id: \.self) { mode in
                    Button { viewModel?.setAutoMode(mode) } label: {
                        Text(mode.rawValue)
                            .font(.mmdspTiny)
                            .foregroundColor(viewModel?.autoMode == mode ? Color.mmdspBright : Color.mmdspText.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(viewModel?.autoMode == mode ? Color.mmdspSelected : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Divider().background(Color.mmdspBorder)
            Button { viewModel?.toggleRepeat() } label: {
                Text("REPEAT").font(.mmdspTiny)
                    .foregroundColor(viewModel?.repeatEnabled ?? true ? Color.mmdspBright : Color.mmdspText.opacity(0.4))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(viewModel?.pdxFileName ?? "(no PDX)")
                .font(.mmdspSmall)
                .foregroundColor(Color.mmdspCyan)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .trailing)
                .padding(.horizontal, 12)
        }
        .background(Color.mmdspBackground.opacity(0.95))
    }

    private var playPauseLabel: String {
        guard let vm = viewModel else { return "▶" }
        switch vm.status {
        case .playing: return "❚❚"
        case .paused:  return "▶"
        case .stopped: return "▶"
        }
    }

    private func playNext() {
        guard let viewModel, let browserVM,
              let idx = viewModel.nextFileIndex(fileItems: browserVM.fileItems, playingIndex: browserVM.playingIndex)
        else { return }

        let files = browserVM.fileItems.filter { !$0.isDirectory }
        guard idx < files.count else { return }

        browserVM.playingIndex = idx
        Task {
            await viewModel.load(url: files[idx].url)
            viewModel.play()
        }
    }

    private func playPrev() {
        guard let viewModel, let browserVM,
              let idx = viewModel.prevFileIndex(fileItems: browserVM.fileItems, playingIndex: browserVM.playingIndex)
        else { return }

        let files = browserVM.fileItems.filter { !$0.isDirectory }
        guard idx < files.count else { return }

        browserVM.playingIndex = idx
        Task {
            await viewModel.load(url: files[idx].url)
            viewModel.play()
        }
    }
}

private struct PanelButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.mmdspMono).foregroundColor(Color.mmdspAmber)
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color.mmdspBackground)
        .overlay(Rectangle().stroke(Color.mmdspBorder, lineWidth: 0.5))
    }
}
