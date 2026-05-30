import SwiftUI

/// レベルメーター: 16 チャンネル分 (FM8ch + PCM8ch) 固定幅
struct LevelMeterView: View {
    let viewModel: PlayerViewModel?
    @State private var keyboardHovered: Int? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text("LEVEL")
                .font(.mp4mSmall)
                .foregroundColor(Color.mp4mCyan)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 3)
            GeometryReader { geo in
                let channels = viewModel?.channels ?? []
                let mutedSet = viewModel?.mutedChannels ?? []
                let chCount = AudioConstants.channelCount
                let spacing: CGFloat = 1
                let totalSpacing = spacing * CGFloat(chCount - 1)
                let chW = max(4, (geo.size.width - totalSpacing) / CGFloat(chCount))
                let labelH: CGFloat = 28
                let barAreaTop: CGFloat = labelH
                let barBottom: CGFloat = geo.size.height - 2
                let barHeight = max(0, barBottom - barAreaTop)

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        for ch in 0..<chCount {
                            let x = CGFloat(ch) * (chW + spacing)
                            let isMuted = mutedSet.contains(ch)
                            let state = ch < channels.count ? channels[ch] : ChannelDisplayState()
                            let mutedOpacity: CGFloat = isMuted ? 0.4 : 1.0

                            // CH number label
                            ctx.draw(
                                Text("\(ch + 1)")
                                    .font(.mp4mTiny)
                                    .foregroundColor(Color.mp4mCyan.opacity(0.7 * mutedOpacity)),
                                at: CGPoint(x: x + chW / 2, y: 8)
                            )

                            // PAN label
                            let panText = state.displayPan(isPCMChannel: ch >= AudioConstants.fmChannelCount)
                            if !panText.isEmpty {
                                ctx.draw(
                                    Text(panText)
                                        .font(.mp4mTiny)
                                        .foregroundColor(state.displayPanColor),
                                    at: CGPoint(x: x + chW / 2, y: 22)
                                )
                            }

                            // 現在のレベル
                            let currentLevel: CGFloat = state.keyOn ? state.displayLevel : 0

                            ctx.opacity = mutedOpacity

                            // レベルバー背景
                            let bgRect = CGRect(x: x + 1, y: barAreaTop, width: chW - 2, height: barHeight)
                            ctx.fill(Path(bgRect), with: .color(Color.mp4mDim.opacity(0.12)))

                            // レベルバー（現在値）
                            if currentLevel > 0 {
                                let fillH = barHeight * currentLevel
                                let fillRect = CGRect(x: x + 1, y: barBottom - fillH, width: chW - 2, height: fillH)
                                let gradient = Gradient(colors: [
                                    Color.mp4mBright.opacity(0.7),
                                    Color.mp4mBright
                                ])
                                ctx.fill(
                                    Path(fillRect),
                                    with: .linearGradient(
                                        gradient,
                                        startPoint: CGPoint(x: x, y: barBottom),
                                        endPoint: CGPoint(x: x, y: barBottom - fillH)
                                    )
                                )
                            }

                            ctx.opacity = 1.0
                        }
                    }

                    // ダブルタップ判定用の透明オーバーレイ
                    HStack(spacing: spacing) {
                        ForEach(0..<chCount, id: \.self) { ch in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    viewModel?.toggleChannel(ch)
                                }
                                .onHover { hovering in
                                    keyboardHovered = hovering ? ch : nil
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 2)
        }
        .background(Color.mp4mBackground)
        .border(Color.mp4mBorder, width: 0.5)
    }
}

// MARK: - チャンネル色表示ロジック（View 固有、Model から分離）

private extension ChannelDisplayState {
    var displayPanColor: Color {
        guard keyOn else { return .clear }
        switch pan {
        case 0: return Color.mp4mCyan.opacity(0.8)
        case 2: return Color.mp4mAmber.opacity(0.8)
        default: return Color.mp4mBright.opacity(0.8)
        }
    }
}
