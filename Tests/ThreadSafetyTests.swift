import XCTest
@testable import MP4M

final class ThreadSafetyTests: XCTestCase {
    @MainActor
    var viewModel: PlayerViewModel?

    @MainActor
    override func setUp() {
        super.setUp()
        viewModel = PlayerViewModel(audioService: MXDRVAudioEngine())
    }

    @MainActor
    override func tearDown() {
        viewModel?.cleanup()
        viewModel = nil
        super.tearDown()
    }

    @MainActor
    func testMainActorPropertyAccess() {
        // @MainActor 隔離された ViewModel のプロパティに安全にアクセスできることを確認
        guard let vm = viewModel else {
            XCTFail("ViewModel is nil")
            return
        }

        XCTAssertEqual(vm.channels.count, AudioConstants.channelCount)
        XCTAssertEqual(vm.spectrumBars.count, AudioConstants.spectrumBinCount)
        XCTAssertEqual(vm.status, .stopped)
    }
}
