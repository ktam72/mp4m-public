import XCTest
@testable import MP4M

final class SpectrumComputeTests: XCTestCase {
    var service: SpectrumComputeService?

    override func setUp() {
        super.setUp()
        service = SpectrumComputeService()
    }

    func testComputeSpectrum_EmptyChannels() {
        let channels = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
        let currentBars = Array(repeating: SpectrumBarState(), count: AudioConstants.spectrumBinCount)

        let result = service?.computeSpectrum(for: channels, currentBars: currentBars)

        XCTAssertNotNil(result)
        // 実装では currentBars をそのまま返すため、入力と同じサイズになる
        XCTAssertEqual(result?.count, currentBars.count)
        // すべてのチャンネルが keyOn = false のため、すべてのバーが current = 0
        for bar in result ?? [] {
            XCTAssertEqual(bar.current, 0)
        }
    }

    func testComputeSpectrum_ActiveChannel() {
        var channels = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
        channels[0].keyOn = true
        channels[0].keyCode = 60  // C4
        channels[0].velocity = 100

        let currentBars = Array(repeating: SpectrumBarState(), count: AudioConstants.spectrumBinCount)

        let result = service?.computeSpectrum(for: channels, currentBars: currentBars)

        XCTAssertNotNil(result)
        // アクティブチャンネルがあるので、いくつかのバーが変化しているはず
        let hasNonZero = result?.contains { $0.current > 0 } ?? false
        XCTAssertTrue(hasNonZero)
    }
}
