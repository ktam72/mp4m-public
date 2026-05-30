import XCTest
@testable import MP4M

final class ChannelStateTests: XCTestCase {
    func testDisplayPan_FMChannel() {
        var state = ChannelDisplayState()
        state.keyOn = true
        state.pan = 0  // L
        XCTAssertEqual(state.displayPan(isPCMChannel: false), "L")

        state.pan = 2  // R
        XCTAssertEqual(state.displayPan(isPCMChannel: false), "R")

        state.pan = 1  // C
        XCTAssertEqual(state.displayPan(isPCMChannel: false), "C")

        state.pan = 3  // LR
        XCTAssertEqual(state.displayPan(isPCMChannel: false), "LR")
    }

    func testDisplayPan_PCMChannel() {
        var state = ChannelDisplayState()
        state.keyOn = true
        state.pan = 3  // PCMチャンネルでは C 固定
        XCTAssertEqual(state.displayPan(isPCMChannel: true), "C")
    }

    func testDisplayLevel() {
        var state = ChannelDisplayState()
        state.keyOn = true
        state.volume = 15  // 最大
        XCTAssertEqual(state.displayLevel, 1.0, accuracy: 0.01)

        state.volume = 0
        XCTAssertEqual(state.displayLevel, 0.0, accuracy: 0.01)

        state.keyOn = false
        XCTAssertEqual(state.displayLevel, 0.0, accuracy: 0.01)
    }

    func testKeyOn() {
        var state = ChannelDisplayState()
        state.keyOn = true
        XCTAssertTrue(state.keyOn)

        state.keyOn = false
        XCTAssertFalse(state.keyOn)
    }
}
