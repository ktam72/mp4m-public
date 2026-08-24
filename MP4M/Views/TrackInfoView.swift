import SwiftUI

/// 曲情報バー: タイトル / 経過時間 / 総時間
struct TrackInfoView: View {
    let viewModel: PlayerViewModel?
    @Binding var showAbout: Bool

    private var elapsedStr: String {
        guard let vm = viewModel else { return "--:--" }
        return formatTime(vm.currentTimeMs)
    }

    private var totalStr: String {
        guard let vm = viewModel, vm.totalTimeMs > 0 else { return "--:--" }
        return formatTime(vm.totalTimeMs)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                Text("mp4m \(version)")
                    .font(.mp4mTitle)
                Text("by ktam72")
                    .font(.mp4mTiny)
                    .foregroundColor(Color.mp4mAmber.opacity(0.7))
            }
                .foregroundColor(Color.mp4mAmber)
                .frame(width: 160)
                .padding(.horizontal, 8)
                .onTapGesture { showAbout = true }
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            Divider().background(Color.mp4mBorder)

            // 曲名折り返し表示（ネオン調）
            Text(viewModel?.title.isEmpty ?? true ? "---" : viewModel?.title ?? "---")
                .font(.mp4mText)
                .foregroundColor(Color.mp4mBright)
                .shadow(color: Color.mp4mBright.opacity(0.6), radius: 12)
                .shadow(color: Color.mp4mBright.opacity(0.3), radius: 24)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

            Divider().background(Color.mp4mBorder)
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(elapsedStr).font(.mp4mMono).foregroundColor(Color.mp4mAmber)
                    Text("/").font(.mp4mMono).foregroundColor(Color.mp4mText.opacity(0.5))
                    Text(totalStr).font(.mp4mMono).foregroundColor(Color.mp4mText.opacity(0.7))
                }
                SeekBarView(viewModel: viewModel)
            }
            .frame(width: 160)
            .padding(.horizontal, 8)
        }
        .background(Color.mp4mBackground.opacity(0.95))
    }

    private func formatTime(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 経過時間のシークバー
///
/// クリックでその位置へ、ドラッグ中はつまみが追従し離した時点でシークする。
private struct SeekBarView: View {
    let viewModel: PlayerViewModel?

    /// ドラッグ中の位置（0.0〜1.0）。ドラッグしていないときは nil
    @State private var dragProgress: Double?

    private static let barHeight: CGFloat = 6

    private var isEnabled: Bool {
        guard let vm = viewModel else { return false }
        return vm.totalTimeMs > 0 && vm.status != .stopped
    }

    private var progress: Double {
        if let dragProgress { return dragProgress }
        guard let vm = viewModel, vm.totalTimeMs > 0 else { return 0 }
        return min(max(Double(vm.currentTimeMs) / Double(vm.totalTimeMs), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.mp4mDim.opacity(0.25))
                Capsule()
                    .fill(isEnabled ? Color.mp4mAmber : Color.mp4mDim.opacity(0.4))
                    .frame(width: width * progress)
                    .opacity(viewModel?.isSeeking == true ? 0.5 : 1.0)
            }
            .frame(height: Self.barHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        dragProgress = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard isEnabled, let vm = viewModel else { return }
                        let ratio = min(max(value.location.x / width, 0), 1)
                        dragProgress = nil
                        Task { await vm.seek(toMs: Int(Double(vm.totalTimeMs) * ratio)) }
                    }
            )
            .onHover { isHovered in
                guard isEnabled else { return }
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .frame(height: Self.barHeight)
    }
}
