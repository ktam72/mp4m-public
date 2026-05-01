import SwiftUI

/// レベルメーター: 16 チャンネル分 (FM8ch + PCM8ch) 固定幅
struct LevelMeterView: View {
    let viewModel: PlayerViewModel?
    private let maxChannels = 16

    var body: some View {
        VStack(spacing: 2) {
            Text("LEVEL")
                .font(.mmdspSmall)
                .foregroundColor(Color.mmdspCyan)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            HStack(spacing: 3) {
                ForEach(0..<maxChannels, id: \.self) { ch in
                    ChannelMeterView(
                        channelIndex: ch,
                        channel: ch < (viewModel?.channels.count ?? 0) ? viewModel?.channels[ch] : nil
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(Color.mmdspBackground)
    }
}

private struct ChannelMeterView: View {
    let channelIndex: Int
    let channel: ChannelDisplayState?

    private var panLabel: String {
        guard let ch = channel, ch.keyOn else { return "" }
        switch ch.pan {
        case 0: return "L"
        case 2: return "R"
        default: return "C"
        }
    }

    private var panColor: Color {
        guard let ch = channel, ch.keyOn else { return .clear }
        switch ch.pan {
        case 0: return Color.mmdspCyan.opacity(0.8)
        case 2: return Color.mmdspAmber.opacity(0.8)
        default: return Color.mmdspBright.opacity(0.8)
        }
    }

    private var level: CGFloat {
        guard let ch = channel, ch.keyOn, ch.velocity > 0 else { return 0 }
        let v = CGFloat(ch.velocity) / 127.0
        return pow(v, 3.0)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("\(channelIndex + 1)")
                .font(.mmdspTiny)
                .foregroundColor(Color.mmdspCyan.opacity(0.7))
            Text(panLabel)
                .font(.mmdspTiny)
                .foregroundColor(channel?.keyOn == true ? panColor : Color.mmdspDim.opacity(0.3))
                .frame(width: 10)
            ZStack(alignment: .bottom) {
                if channel?.keyOn == true {
                    Rectangle()
                        .fill(Color.mmdspDim.opacity(0.15))
                    Rectangle()
                        .fill(Color.mmdspBright)
                        .frame(height: maxBarHeight * level)
                }
            }
            .frame(height: maxBarHeight)
        }
        .frame(minWidth: 16, maxWidth: .infinity)
    }

    private let maxBarHeight: CGFloat = 130
}
