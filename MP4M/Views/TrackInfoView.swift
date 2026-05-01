import SwiftUI

/// 曲情報バー: タイトル / 経過時間 / 総時間
struct TrackInfoView: View {
    let viewModel: PlayerViewModel?

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
            Text("MDXPlayer for macOS β")
                .font(.mmdspTitle)
                .foregroundColor(Color.mmdspAmber)
                .frame(width: 160)
                .padding(.horizontal, 8)
            Divider().background(Color.mmdspBorder)
            Text(viewModel?.title.isEmpty ?? true ? "---" : viewModel?.title ?? "---")
                .font(.mmdspText)
                .foregroundColor(Color.mmdspBright)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            Divider().background(Color.mmdspBorder)
            HStack(spacing: 4) {
                Text(elapsedStr).font(.mmdspMono).foregroundColor(Color.mmdspAmber)
                Text("/").font(.mmdspMono).foregroundColor(Color.mmdspText.opacity(0.5))
                Text(totalStr).font(.mmdspMono).foregroundColor(Color.mmdspText.opacity(0.7))
            }
            .frame(width: 130)
            .padding(.horizontal, 8)
            Divider().background(Color.mmdspBorder)
            Text("MXDRV")
                .font(.mmdspSmall)
                .foregroundColor(Color.mmdspCyan)
                .frame(width: 60)
                .padding(.horizontal, 4)
        }
        .background(Color.mmdspBackground.opacity(0.95))
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
