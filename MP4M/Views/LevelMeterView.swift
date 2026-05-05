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

    var body: some View {
        VStack(spacing: 1) {
            Text("\(channelIndex + 1)")
                .font(.mp4mTiny)
                .foregroundColor(Color.mp4mCyan.opacity(0.7))
                .onTapGesture(count: 2) {
                    onDoubleTap()
                }
            Text(channel?.displayPan(isPCMChannel: channelIndex >= 8) ?? "")
                .font(.mp4mTiny)
                .foregroundColor(channel?.displayPanColor ?? Color.mp4mDim.opacity(0.3))
                .frame(width: 10)
            ZStack(alignment: .bottom) {
                if channel?.keyOn == true {
                    Rectangle()
                        .fill(Color.mp4mDim.opacity(0.15))
                    Rectangle()
                        .fill(Color.mp4mBright)
                        .frame(height: maxBarHeight * (channel?.displayLevel ?? 0))
                }
            }
            .frame(height: maxBarHeight)
        }
        .frame(minWidth: 16, maxWidth: .infinity)
        .opacity(isMuted ? 0.4 : 1.0)
    }

    private let maxBarHeight: CGFloat = 130
}
