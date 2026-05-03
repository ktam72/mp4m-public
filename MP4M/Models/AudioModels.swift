import Foundation

// MARK: - 再生状態

enum PlayStatus {
    case stopped
    case playing
    case paused
}

enum AutoMode: String, CaseIterable {
    case normal  = "NORMAL"
    case auto    = "AUTO"
    case shuffle = "SHUFFLE"
}

// MARK: - チャンネル表示データ

struct ChannelDisplayState {
    var keyCode: UInt8 = 0
    var velocity: UInt8 = 0
    var keyOn: Bool = false
    var volume: UInt8 = 0
    var bend: Int16 = 0
    var pan: UInt8 = 1
    var keyOffset: UInt8 = 0
}

// MARK: - スペアナバー状態

struct SpectrumBarState {
    var current: Float = 0
    var peak: Float = 0
    var peakTimer: Int = 0
}
