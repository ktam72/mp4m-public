import Foundation

/// オーディオ処理全体で使用する定数
enum AudioConstants {
    /// FM + PCM の全チャンネル数
    static let channelCount = 16
    /// FM チャンネル数
    static let fmChannelCount = 8
    /// PCM チャンネル数
    static let pcmChannelCount = 8

    /// スペクトラム内部ビン数（GPU バッファサイズ）
    static let spectrumBinCount = 52
    /// 表示用スペアナバー数
    static let displayBarCount = 32

    /// 表示更新フレームレート（fps）
    static let frameRate = 120
}
