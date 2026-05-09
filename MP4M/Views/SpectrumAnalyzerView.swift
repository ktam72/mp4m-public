import SwiftUI

/// スペアナ: 32 バー + ピーク保持
struct SpectrumAnalyzerView: View {
    let viewModel: PlayerViewModel?
    private let barCount = 32
    private let maxLevel: Float = 28

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let bars = viewModel?.spectrumBars ?? []
                let barW = size.width / CGFloat(barCount)
                let gap: CGFloat = 1
                for index in 0..<barCount {
                    let bar = index < bars.count ? bars[index] : SpectrumBarState()
                    let ratio = min(CGFloat(bar.current / maxLevel), 1.0)
                    let peakRatio = min(CGFloat(bar.peak / maxLevel), 1.0)
                    let barX = CGFloat(index) * barW
                    let barHeight = ratio * size.height
                    let barRect = CGRect(
                        x: barX + gap / 2,
                        y: size.height - barHeight,
                        width: barW - gap,
                        height: barHeight
                    )
                    let gradient = Gradient(colors: [
                        Color.mp4mBright.opacity(0.7),
                        Color.mp4mBright
                    ])
                    ctx.fill(
                        Path(barRect),
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: barX, y: size.height),
                            endPoint: CGPoint(x: barX, y: size.height - barHeight)
                        )
                    )
                    if bar.peak > 0 {
                        let peakY = size.height - peakRatio * size.height - 2
                        let peakRect = CGRect(x: barX + gap / 2, y: peakY, width: barW - gap, height: 2)
                        ctx.fill(Path(peakRect), with: .color(Color.mp4mPeak))
                    }
                }
                for level in [0.25, 0.5, 0.75] {
                    let lineY = size.height * (1 - CGFloat(level))
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: lineY))
                    path.addLine(to: CGPoint(x: size.width, y: lineY))
                    ctx.stroke(path, with: .color(Color.mp4mDim), lineWidth: 0.5)
                }
            }
            .background(Color.mp4mBackground)
        }
    }
}
