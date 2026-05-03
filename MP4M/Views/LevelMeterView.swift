import SwiftUI

/// レベルメーター: 16 チャンネル分 (FM8ch + PCM8ch) 固定幅
struct LevelMeterView: View {
    let viewModel: PlayerViewModel?
    private let maxChannels = 16

    var body: some View {
        VStack(spacing: 1) {
            Text("LEVEL")
                .font(.mp4mSmall)
                .foregroundColor(Color.mp4mCyan)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 3)
            HStack(spacing: 3) {
                ForEach(0..<maxChannels, id: \.self) { ch in
                    ChannelMeterView(
                        channelIndex: ch,
                        channel: ch < (viewModel?.channels.count ?? 0) ? viewModel?.channels[ch] : nil,
                        isMuted: viewModel?.mutedChannels.contains(ch) ?? false,
                        onDoubleTap: { viewModel?.toggleChannel(ch) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 2)
        }
        .background(Color.mp4mBackground)
        .border(Color.mp4mBorder, width: 0.5)
    }
}

private struct ChannelMeterView: View {
    let channelIndex: Int
    let channel: ChannelDisplayState?
    let isMuted: Bool
    let onDoubleTap: () -> Void

    private var panLabel: String {
        guard let ch = channel, ch.keyOn else { return "" }
        // PCMチャンネル (9-16ch, index 8-15) はステレオでも C 表示
        if channelIndex >= 8 && ch.pan == 3 {
            return "C"
        }
        switch ch.pan {
        case 0: return "L"
        case 2: return "R"
        case 3: return "LR"
        default: return "C"
        }
    }

    private var panColor: Color {
        guard let ch = channel, ch.keyOn else { return .clear }
        switch ch.pan {
        case 0: return Color.mp4mCyan.opacity(0.8)
        case 2: return Color.mp4mAmber.opacity(0.8)
        default: return Color.mp4mBright.opacity(0.8)
        }
    }

    private var level: CGFloat {
        guard let ch = channel, ch.keyOn else { return 0 }
        // volume を 0-15 スケール（最大値 15 = 100%）で線形表示
        let normalized = min(CGFloat(ch.volume) / 15.0, 1.0)
        return normalized
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("\(channelIndex + 1)")
                .font(.mp4mTiny)
                .foregroundColor(Color.mp4mCyan.opacity(0.7))
                .onTapGesture(count: 2) {
                    onDoubleTap()
                }
            Text(panLabel)
                .font(.mp4mTiny)
                .foregroundColor(channel?.keyOn == true ? panColor : Color.mp4mDim.opacity(0.3))
                .frame(width: 10)
            ZStack(alignment: .bottom) {
                if channel?.keyOn == true {
                    Rectangle()
                        .fill(Color.mp4mDim.opacity(0.15))
                    Rectangle()
                        .fill(Color.mp4mBright)
                        .frame(height: maxBarHeight * level)
                }
            }
            .frame(height: maxBarHeight)
        }
        .frame(minWidth: 16, maxWidth: .infinity)
        .opacity(isMuted ? 0.4 : 1.0)
    }

    private let maxBarHeight: CGFloat = 130
}
