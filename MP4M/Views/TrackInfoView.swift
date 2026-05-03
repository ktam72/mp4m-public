import SwiftUI

/// 曲情報バー: タイトル / 経過時間 / 総時間
struct TrackInfoView: View {
    let viewModel: PlayerViewModel?
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTimer: Timer?
    @State private var lastTitle: String = ""

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
            Divider().background(Color.mp4mBorder)

            // 曲名スクロール表示
            ZStack(alignment: .leading) {
                Color.clear
                Text(viewModel?.title.isEmpty ?? true ? "---" : viewModel?.title ?? "---")
                    .font(.mp4mText)
                    .foregroundColor(Color.mp4mBright)
                    .lineLimit(1)
                    .offset(x: scrollOffset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
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
        .onChange(of: viewModel?.title) { oldValue, newValue in
            handleTitleChange(newValue ?? "")
        }
        .onAppear {
            startScrolling()
        }
        .onDisappear {
            stopScrolling()
        }
    }

    private func handleTitleChange(_ newTitle: String) {
        scrollOffset = 0
        lastTitle = newTitle
        stopScrolling()
        startScrolling()
    }

    private func startScrolling() {
        let displayTitle = viewModel?.title.isEmpty ?? true ? "---" : viewModel?.title ?? "---"
        guard !displayTitle.isEmpty && displayTitle != "---" else {
            scrollOffset = 0
            return
        }

        let titleWidth = displayTitle.count * 8
        let viewportWidth = 300

        if titleWidth > viewportWidth {
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                withAnimation(.linear(duration: 0)) {
                    scrollOffset -= 1
                    if abs(scrollOffset) > CGFloat(titleWidth) {
                        scrollOffset = 0
                    }
                }
            }
        } else {
            scrollOffset = 0
            stopScrolling()
        }
    }

    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
