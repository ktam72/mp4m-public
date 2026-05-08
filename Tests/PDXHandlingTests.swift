import XCTest
@testable import MP4M
import AudioToolbox

final class PDXHandlingTests: XCTestCase {
    var audioService: MXDRVAudioEngine?

    override func setUp() {
        super.setUp()
        audioService = MXDRVAudioEngine()
        audioService?.start(sampleRate: 44100)
    }

    override func tearDown() {
        audioService?.end()
        audioService = nil
        super.tearDown()
    }

    func testPDXLoadError_InvalidFile() {
        // 存在しないファイルパスを渡すとエラーになるはず
        let expectation = self.expectation(description: "Load invalid file")

        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try self?.audioService?.loadMDXFile(path: "/invalid/path/test.mdx")
                }.value
                XCTFail("Expected error to be thrown")
            } catch MP4MError.fileAccessDenied(_) {
                // 期待通り
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }
}
