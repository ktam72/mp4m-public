import Foundation
import Metal

/// スペクトラムアナライザーの計算を担当するサービス
/// GPU (Metal) または CPU でビンマッピング + 拡散を計算
///
/// スペアナの計算ロジックをViewから分離し、テスト可能性を高める
final class SpectrumComputeService {
    private let metalCompute: MetalSpectrumCompute?
    private let routeTable: [Float] = [
        0, 1, 4, 9, 16, 24, 35, 47, 61, 77, 94,
        113, 133, 155, 179, 204, 230, 258, 287, 317, 348,
        381, 415, 450, 486, 523, 561, 600, Float.greatestFiniteMagnitude
    ]
    private let riseTable: [Int] = [1, 1, 2, 2, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8, 8,
                                     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]

    init() {
        self.metalCompute = MetalSpectrumCompute()
    }

    /// チャンネル状態からスペクトラムバー状態を計算
    ///
    /// - Parameters:
    ///   - channels: チャンネル表示状態（最大16ch）
    ///   - currentBars: 現在のバー状態（UIに表示中の状態）
    /// - Returns: 更新されたスペクトラムバー状態（32バー分）
    /// - Note: GPU (Metal) が利用可能な場合はGPUで計算、不可時はCPUで計算
    func computeSpectrum(for channels: [ChannelDisplayState], currentBars: [SpectrumBarState]) -> [SpectrumBarState] {
        // GPU または CPU でビンマッピング + 拡散を計算
        let speaBuf = metalCompute?.computeSpectrum(channels: channels) ?? computeSpectrumCPU(channels: channels)

        // バー状態更新
        var newBars = currentBars
        let maxBars = Float(routeTable.count - 1)
        for i in 0..<32 {
            var bar = newBars[i]
            let raw = speaBuf[i + 5]
            var targetBar: Float = 0

            if raw > 0 {
                for j in 0..<routeTable.count {
                    if raw < routeTable[j] {
                        if bar.current < Float(j) { targetBar = Float(j) }
                        break
                    }
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
            newBars[i] = bar
        }

        return newBars
    }

    /// CPU版スペクトラム計算（ビンマッピング + 拡散）
    /// Metal が利用不可時のフォールバック用
    private func computeSpectrumCPU(channels: [ChannelDisplayState]) -> [Float] {
        var bins = [Float](repeating: 0, count: 52)

        for ch in channels {
            guard ch.keyOn else { continue }
            let midiNote = Int(ch.keyCode)
            let velocity = Float(ch.velocity) / 127.0

            // MIDI ノート → 周波数ビンマッピング
            let binIndex = midiNote / 12 * 4 + (midiNote % 12) / 3
            guard binIndex >= 0, binIndex < bins.count else { continue }

            // 拡散ロジック：周辺ビンに振幅を分散
            let spreadFactors: [Float] = [1.0, 3.0 / 4.0, 5.0 / 16.0, 1.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0]
            let offsets = [0, -1, -2, 1, 2, 3]

            for (offset, factor) in zip(offsets, spreadFactors) {
                let targetBin = binIndex + offset
                guard targetBin >= 0, targetBin < bins.count else { continue }
                bins[targetBin] += velocity * factor
            }
        }

        return bins
    }
}
