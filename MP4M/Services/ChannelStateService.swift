import Foundation

/// チャンネル状態の取得・キャッシングを担当するサービス
/// 更新頻度を制御してCPU負荷を軽減
final class ChannelStateService {
    private let audioService: any AudioEngineService
    private var lastChannelStateUpdateMs: Int = 0
    private var cachedChannels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: 16)
    private let channelStateUpdateIntervalMs: Int = 200  // 200ms ごとにのみ取得

    init(audioService: any AudioEngineService) {
        self.audioService = audioService
    }

    /// チャンネル状態を取得（キャッシング付き）
    /// - Parameter currentTimeMs: 現在の再生時間(ms)
    /// - Returns: チャンネル表示状態
    func getChannels(currentTimeMs: Int) -> [ChannelDisplayState] {
        if (currentTimeMs - lastChannelStateUpdateMs) >= channelStateUpdateIntervalMs {
            cachedChannels = audioService.getChannelStates()
            lastChannelStateUpdateMs = currentTimeMs
        }
        return cachedChannels
    }

    /// キャッシュをリセット
    func resetCache() {
        lastChannelStateUpdateMs = 0
        cachedChannels = Array(repeating: ChannelDisplayState(), count: 16)
    }
}
