import XCTest
@testable import MP4M

final class SpectrumComputeTests: XCTestCase {
    var service: SpectrumComputeService?
    
    override func setUp() {
        super.setUp()
        service = SpectrumComputeService()
    }
    
    func testComputeSpectrum_EmptyChannels() {
        let channels = Array(repeating: ChannelDisplayState(), count: 16)
        let currentBars = Array(repeating: SpectrumBarState(), count: 52)
        
        let result = service?.computeSpectrum(for: channels, currentBars: currentBars)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 52)
    }
    
    func testComputeSpectrum_ActiveChannel() {
        var channels = Array(repeating: ChannelDisplayState(), count: 16)
        channels[0].keyOn = true
        channels[0].keyCode = 60  // C4
        channels[0].velocity = 100
        
        let currentBars = Array(repeating: SpectrumBarState(), count: 52)
        
        let result = service?.computeSpectrum(for: channels, currentBars: currentBars)
        
        XCTAssertNotNil(result)
        // アクティブチャンネルがあるので、いくつかのバーが変化しているはず
        let hasNonZero = result?.contains { $0.current > 0 } ?? false
        XCTAssertTrue(hasNonZero)
    }
}
