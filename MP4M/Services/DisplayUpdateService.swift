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
}
