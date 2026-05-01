import SwiftUI

/// スペアナ: 32 バー + ピーク保持
struct SpectrumAnalyzerView: View {
    let viewModel: PlayerViewModel?
    private let barCount = 32
    private let maxLevel: Float = 28

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let bars = viewModel?.spectrumBars ?? []
                let barW = size.width / CGFloat(barCount)
                let gap: CGFloat = 1
                for i in 0..<barCount {
                    let bar = i < bars.count ? bars[i] : SpectrumBarState()
                    let ratio = CGFloat(bar.current / maxLevel)
                    let peakRatio = CGFloat(bar.peak / maxLevel)
                    let x = CGFloat(i) * barW
                    let barHeight = ratio * size.height
                    let barRect = CGRect(
                        x: x + gap / 2,
                        y: size.height - barHeight,
                        width: barW - gap,
                        height: barHeight
                    )
                    let gradient = Gradient(colors: [
                        Color.mmdspBright.opacity(0.7),
                        Color.mmdspBright
                    ])
                    ctx.fill(
                        Path(barRect),
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: x, y: size.height),
                            endPoint: CGPoint(x: x, y: size.height - barHeight)
                        )
                    )
                    if bar.peak > 0 {
                        let py = size.height - peakRatio * size.height - 2
                        let peakRect = CGRect(x: x + gap / 2, y: py, width: barW - gap, height: 2)
                        ctx.fill(Path(peakRect), with: .color(Color.mmdspPeak))
                    }
                }
                for level in [0.25, 0.5, 0.75] {
                    let y = size.height * (1 - CGFloat(level))
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(Color.mmdspDim), lineWidth: 0.5)
                }
            }
            .background(Color.mmdspBackground)
        }
    }
}
