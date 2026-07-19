import Foundation

/// スペクトラムアナライザーの計算を担当するサービス
/// CPU でビンマッピング + 拡散を計算
///
/// 計算は 16ch × 数演算と極小のため CPU が最速
/// （GPU 同期ディスパッチは往復オーバーヘッドが計算本体の千倍以上になるため不採用）
///
/// スペアナの計算ロジックをViewから分離し、テスト可能性を高める
final class SpectrumComputeService {
    private let routeTable: [Float] = [
        0, 1, 4, 9, 16, 24, 35, 47, 61, 77, 94,
        113, 133, 155, 179, 204, 230, 258, 287, 317, 348,
        381, 415, 450, 486, 523, 561, 600, Float.greatestFiniteMagnitude
    ]
    private let riseTable: [Int] = [1, 1, 2, 2, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8, 8,
                                     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]

    /// チャンネル状態からスペクトラムバー状態を計算
    ///
    /// - Parameters:
    ///   - channels: チャンネル表示状態（最大16ch）
    ///   - currentBars: 現在のバー状態（UIに表示中の状態）
    /// - Returns: 更新されたスペクトラムバー状態（32バー分）
    func computeSpectrum(for channels: [ChannelDisplayState], currentBars: [SpectrumBarState]) -> [SpectrumBarState] {
        // ビンマッピング + 拡散を計算
        let speaBuf = computeSpectrumCPU(channels: channels)

        // バー状態更新
        var newBars = currentBars
        let maxBars = Float(routeTable.count - 1)
        for barIndex in 0..<AudioConstants.displayBarCount {
            var bar = newBars[barIndex]
            let raw = speaBuf[barIndex + 5]
            var targetBar: Float = 0

            if raw > 0 {
                for routeIndex in 0..<routeTable.count where raw < routeTable[routeIndex] {
                    if bar.current < Float(routeIndex) { targetBar = Float(routeIndex) }
                    break
                }
            }

            if targetBar > bar.current {
                let diff = Int(targetBar - bar.current)
                let rise = Float(diff < riseTable.count ? riseTable[diff] : 8)
                bar.current = min(bar.current + rise, maxBars)
            } else if targetBar < bar.current {
                let diff = bar.current - targetBar
                bar.current -= (diff > 2) ? 2 : diff
            }

            if bar.peakTimer > 0 { bar.peakTimer -= 1 }
            if bar.peakTimer == 0, bar.peak > 0 { bar.peak -= 1 }
            if bar.peak < targetBar {
                bar.peak = targetBar
                bar.peakTimer = 10
            }
            newBars[barIndex] = bar
        }

        return newBars
    }

    /// スペクトラム計算（ビンマッピング + 拡散）
    /// 旧 Spectrum.metal (computeSpectrum カーネル) と同一のロジック
    private func computeSpectrumCPU(channels: [ChannelDisplayState]) -> [Float] {
        var bins = [Float](repeating: 0, count: AudioConstants.spectrumBinCount)

        // 拡散係数（中心から ±1..±5 ビンへ左右対称に分散）
        let spreadFactors: [Float] = [0.75, 0.3125, 0.125, 0.25, 0.0625]

        for channel in channels {
            guard channel.keyOn else { continue }

            // キーコード + オフセット → ビンマッピング（3 半音 = 1 ビン）
            let binIndex = (Int(channel.keyCode) + Int(channel.keyOffset)) / 3
            guard binIndex >= 0, binIndex < 42 else { continue }

            // velocity は正規化せず生値（routeTable の閾値 0〜600 に対応）
            let amplitude = Float(channel.velocity)

            bins[binIndex] += amplitude
            for (distance, factor) in spreadFactors.enumerated() {
                let offset = distance + 1
                if binIndex - offset >= 0 {
                    bins[binIndex - offset] += amplitude * factor
                }
                if binIndex + offset < bins.count {
                    bins[binIndex + offset] += amplitude * factor
                }
            }
        }

        return bins
    }
}
