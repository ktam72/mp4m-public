import SwiftUI

/// コントロールパネル: 再生操作ボタン + オートモード
struct ControlPanelView: View {
    let viewModel: PlayerViewModel?
    let browserVM: FileBrowserViewModel?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                PanelButton(label: "◀◀", action: playPrev, isEnabled: isFileSelected)
                PanelButton(label: playPauseLabel, action: { viewModel?.togglePlay() }, isEnabled: isFileSelected)
                PanelButton(label: "■", action: { viewModel?.stop() }, isEnabled: isFileSelected)
                PanelButton(label: "▶▶", action: playNext, isEnabled: isFileSelected)
            }
            Divider().background(Color.mp4mBorder)
            HStack(spacing: 4) {
                Text("LOOP:").font(.mp4mSmall).foregroundColor(Color.mp4mText.opacity(0.7))
                Button { viewModel?.setLoopCount((viewModel?.loopCount ?? 2) - 1) } label: {
                    Text("-").font(.mp4mMono).foregroundColor(Color.mp4mAmber)
                }
                .buttonStyle(.plain)
                Text(viewModel?.loopCount == 0 ? "∞" : "\(viewModel?.loopCount ?? 2)")
                    .font(.mp4mMono).foregroundColor(Color.mp4mBright).frame(width: 20)
                Button { viewModel?.setLoopCount((viewModel?.loopCount ?? 2) + 1) } label: {
                    Text("+").font(.mp4mMono).foregroundColor(Color.mp4mAmber)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            Divider().background(Color.mp4mBorder)
            HStack(spacing: 6) {
                ForEach(AutoMode.allCases, id: \.self) { mode in
                    Button { viewModel?.setAutoMode(mode) } label: {
                        Text(mode.rawValue)
                            .font(.mp4mTiny)
                            .foregroundColor(
                                viewModel?.autoMode == mode
                                ? Color.mp4mBright
                                : Color.mp4mText.opacity(0.5)
                            )
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(viewModel?.autoMode == mode ? Color.mp4mSelected : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Divider().background(Color.mp4mBorder)
            Spacer()
            Text(adjustedPdxFileName)
                .font(.mp4mSmall)
                .foregroundColor(Color.mp4mCyan)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .trailing)
                .padding(.horizontal, 12)
        }
        .background(Color.mp4mBackground.opacity(0.95))
    }

    /// ファイルが選択されているかどうかを判定
    private var isFileSelected: Bool {
        guard let browserVM = browserVM else { return false }
        return browserVM.playingIndex >= 0 && browserVM.playingIndex < browserVM.playableFiles.count
    }

    /// PDXファイル名の調整：拡張子がない場合は .pdx を補完（"No PDX" はブリッジ側で正規化済み）
    private var adjustedPdxFileName: String {
        guard let raw = viewModel?.pdxFileName, !raw.isEmpty else {
            return "No PDX"
        }
        // "No PDX" はブリッジ側で既に統一されているため、有効なファイル名の場合のみ拡張子処理
        if raw == "No PDX" {
            return "No PDX"
        }
        if raw.lowercased().hasSuffix(".pdx") {
            return raw
        } else {
            return raw + ".pdx"
        }
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
        guard let viewModel, let browserVM else { return }
        viewModel.playNextFile(browserVM: browserVM)
    }

    private func playPrev() {
        guard let viewModel, let browserVM else { return }
        viewModel.playPrevFile(browserVM: browserVM)
    }
}

private struct PanelButton: View {
    let label: String
    let action: () -> Void
    let isEnabled: Bool

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mp4mMono)
                .foregroundColor(isEnabled ? Color.mp4mAmber : Color.mp4mDim)
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(Color.mp4mBackground)
        .overlay(Rectangle().stroke(Color.mp4mBorder, lineWidth: 0.5))
    }
}
