import Foundation

/// 120fps の MainActor 表示更新ループを管理する
@MainActor
final class DisplayUpdateManager {
    private var task: Task<Void, Never>?
    private(set) var frameCount: Int = 0

    /// 更新ループを開始する
    /// - Parameters:
    ///   - shouldContinue: 継続条件を返すクロージャ（MainActor 上で同期的に評価）
    ///   - update: フレームごとに呼ばれる更新処理（frameCount が渡される）
    func start(
        shouldContinue: @escaping @MainActor () -> Bool,
        update: @escaping @MainActor (Int) async -> Void
    ) {
        task?.cancel()
        frameCount = 0
        task = Task { @MainActor in
            while !Task.isCancelled && shouldContinue() {
                await update(frameCount)
                frameCount += 1
                try? await Task.sleep(for: .seconds(1.0 / 120.0))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func resetFrameCount() {
        frameCount = 0
    }
}
