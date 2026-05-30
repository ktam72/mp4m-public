import Foundation

/// チャンネル状態の取得・キャッシングを担当するサービス
/// 更新頻度を制御してCPU負荷を軽減
///
/// 200msごとにのみ実際の取得を行い、それ以外はキャッシュを返す
final class ChannelStateService {
    private let audioService: any AudioEngineService
    private var lastChannelStateUpdateMs: Int = 0
    private var cachedChannels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
    private let channelStateUpdateIntervalMs: Int = 200  // 200ms ごとにのみ取得

    init(audioService: any AudioEngineService) {
        self.audioService = audioService
    }

    /// チャンネル状態を取得（キャッシング付き）
    ///
    /// - Parameter currentTimeMs: 現在の再生時間(ms)
    /// - Returns: チャンネル表示状態（16ch分）
    /// - Note: 前回の取得から200ms経過している場合のみ新しい状態を取得
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
        cachedChannels = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
    }
}
