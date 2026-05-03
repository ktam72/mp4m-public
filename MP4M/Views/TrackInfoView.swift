import SwiftUI

/// 曲情報バー: タイトル / 経過時間 / 総時間
struct TrackInfoView: View {
    let viewModel: PlayerViewModel?
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTimer: Timer?
    @State private var lastTitle: String = ""
    @State private var isScrolling: Bool = false
    @State private var textWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 300

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
                    .lineLimit(isScrolling ? nil : 1)
                    .offset(x: scrollOffset)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    textWidth = geo.size.width
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        startScrolling()
                                    }
                                }
                                .onChange(of: viewModel?.title) { oldValue, newValue in
                                    textWidth = geo.size.width
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        handleTitleChange(newValue ?? "")
                                    }
                                }
                        }
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .padding(.horizontal, 8)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            viewportWidth = geo.size.width
                        }
                }
            )

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

        // テキスト幅がビューポート幅より大きい場合のみスクロール
        guard textWidth > viewportWidth else {
            scrollOffset = 0
            isScrolling = false
            return
        }

        isScrolling = true
        scrollOffset = 0

        let scrollDistance = textWidth + 30
        let scrollDuration = scrollDistance * 0.05
        let startTime = Date()

        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)

            if elapsed >= scrollDuration {
                // スクロール完了
                DispatchQueue.main.async {
                    self.scrollOffset = -scrollDistance
                    self.isScrolling = false
                }
                timer.invalidate()
            } else {
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 0)) {
                        self.scrollOffset = -CGFloat(elapsed / 0.05)
                    }
                }
            }
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
