import XCTest
@testable import MP4M

final class ThreadSafetyTests: XCTestCase {
    var viewModel: PlayerViewModel?

    override func setUp() {
        super.setUp()
        viewModel = PlayerViewModel(audioService: MXDRVAudioEngine())
    }

    override func tearDown() {
        viewModel?.cleanup()
        viewModel = nil
        super.tearDown()
    }

    func testConcurrentChannelAccess() {
        // 複数スレッドから同時にチャンネル状態にアクセスしてもクラッシュしないか
        guard let vm = viewModel else {
            XCTFail("ViewModel is nil")
            return
        }

        let expectation = self.expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                // 複数回アクセス
                for _ in 0..<100 {
                    _ = vm.channels
                    _ = vm.spectrumBars
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
        // クラッシュしなければ成功
    }
}
