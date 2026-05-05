import Foundation

/// UI更新の管理を担当するサービス
/// フレームレート制御・更新タイミングを管理
final class DisplayUpdateService {
    private var updateFrameCounter: Int = 0

    /// 更新フレームカウンターを進め、フル更新フラグを返す
    /// - Returns: フル更新を行うかどうか（30fps相当）
    func advanceFrame() -> Bool {
        let isFullUpdate = (updateFrameCounter % 2 == 0)
        updateFrameCounter = (updateFrameCounter + 1) % 2
        return isFullUpdate
    }

    /// 再生時間を計算（ローカル時間計測によるC++呼び出し削減）
    /// - Parameters:
    ///   - playStartTimeMs: 再生開始時の時間(ms)
    ///   - playStartDate: 再生開始時刻
    ///   - lastSyncTimeMs: 最後に同期した時間(ms)
    ///   - syncIntervalMs: 同期間隔(ms)
    /// - Returns: (現在の時間ms, 同期が必要か, 更新されたplayStartTimeMs)
    func calculateCurrentTime(
        playStartTimeMs: Int,
        playStartDate: Date,
        lastSyncTimeMs: Int,
        syncIntervalMs: Int
    ) -> (currentTimeMs: Int, needsSync: Bool, updatedStartTimeMs: Int) {
        let elapsedMs = Int(Date().timeIntervalSince(playStartDate) * 1000)
        var ms = playStartTimeMs + elapsedMs

        // 同期が必要かチェック
        let needsSync = abs(ms - lastSyncTimeMs) >= syncIntervalMs

        return (ms, needsSync, playStartTimeMs)
    }

    /// 同期を実行し、更新された値を返す
    /// - Parameter audioService: オーディオサービス
    /// - Returns: (同期後の時間ms, 現在のDate, 更新されたstartTimeMs, 更新されたsyncTimeMs)
    func performSync(audioService: any AudioEngineService) -> (currentTimeMs: Int, currentDate: Date, updatedStartTimeMs: Int, updatedSyncTimeMs: Int) {
        let ms = audioService.currentPlayTimeMs()
        let now = Date()
        return (ms, now, ms, ms)
    }
}
