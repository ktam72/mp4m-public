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
            Text("mp4m β版")
                .font(.mp4mTitle)
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

            // 曲名折り返し表示
            Text(viewModel?.title.isEmpty ?? true ? "---" : viewModel?.title ?? "---")
                .font(.mp4mText)
                .foregroundColor(Color.mp4mBright)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

            Divider().background(Color.mp4mBorder)
            HStack(spacing: 4) {
                Text(elapsedStr).font(.mp4mMono).foregroundColor(Color.mp4mAmber)
                Text("/").font(.mp4mMono).foregroundColor(Color.mp4mText.opacity(0.5))
                Text(totalStr).font(.mp4mMono).foregroundColor(Color.mp4mText.opacity(0.7))
            }
            .frame(width: 130)
            .padding(.horizontal, 8)
        }
        .background(Color.mp4mBackground.opacity(0.95))
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
