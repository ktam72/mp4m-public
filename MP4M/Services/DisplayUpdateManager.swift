import AppKit
import Foundation

/// vsync 同期の MainActor 表示更新ループを管理する
///
/// CADisplayLink（macOS 14+）でディスプレイのリフレッシュに同期し、
/// `AudioConstants.frameRate` を上限とするフレームレートで update を呼び出す。
/// Task.sleep ループと異なりドリフト・ジッタが発生しない。
@MainActor
final class DisplayUpdateManager {
    private var displayLink: CADisplayLink?
    private(set) var frameCount: Int = 0
    private var shouldContinue: (() -> Bool)?
    private var update: ((Int) async -> Void)?
    private var updateTask: Task<Void, Never>?

    /// 更新ループを開始する
    /// - Parameters:
    ///   - shouldContinue: 継続条件を返すクロージャ（MainActor 上で同期的に評価）
    ///   - update: フレームごとに呼ばれる更新処理（frameCount が渡される）
    func start(
        shouldContinue: @escaping @MainActor () -> Bool,
        update: @escaping @MainActor (Int) async -> Void
    ) {
        stop()
        frameCount = 0
        self.shouldContinue = shouldContinue
        self.update = update

        guard let screen = NSScreen.main else {
            startFallbackLoop()
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: Float(AudioConstants.frameRate),
            preferred: Float(AudioConstants.frameRate)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        updateTask?.cancel()
        updateTask = nil
        shouldContinue = nil
        update = nil
    }

    func resetFrameCount() {
        frameCount = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard shouldContinue?() == true else {
            stop()
            return
        }
        // 前フレームの update が未完了ならスキップ（積み上がり防止）
        guard updateTask == nil, let update else { return }
        let frame = frameCount
        frameCount += 1
        updateTask = Task { @MainActor [weak self] in
            await update(frame)
            self?.updateTask = nil
        }
    }

    /// NSScreen が取得できない環境向けのフォールバック（従来の Task.sleep ループ）
    private func startFallbackLoop() {
        updateTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.shouldContinue?() == true {
                if let update = self.update {
                    await update(self.frameCount)
                }
                self.frameCount += 1
                try? await Task.sleep(for: .seconds(1.0 / Double(AudioConstants.frameRate)))
            }
        }
    }
}
