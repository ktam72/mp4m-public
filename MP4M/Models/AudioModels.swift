import Foundation
import SwiftUI

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

// MARK: - ChannelDisplayState 拡張（表示ロジック）
extension ChannelDisplayState {
    /// PAN 表示文字列（L/C/R/LR、PCMチャンネルは pan=3 でも C 固定）
    func displayPan(isPCMChannel: Bool) -> String {
        guard keyOn else { return "" }
        if isPCMChannel && pan == 3 { return "C" }
        switch pan {
        case 0: return "L"
        case 2: return "R"
        case 3: return "LR"
        default: return "C"
        }
    }

    /// PAN 表示色
    var displayPanColor: Color {
        guard keyOn else { return .clear }
        switch pan {
        case 0: return Color.mp4mCyan.opacity(0.8)
        case 2: return Color.mp4mAmber.opacity(0.8)
        default: return Color.mp4mBright.opacity(0.8)
        }
    }

    /// 正規化レベル（0.0〜1.0）
    var displayLevel: CGFloat {
        guard keyOn else { return 0 }
        return min(CGFloat(volume) / 15.0, 1.0)
    }

    /// アクティブ状態（keyOn）
    var isActive: Bool { keyOn }
}

// MARK: - スペアナバー状態

struct SpectrumBarState {
    var current: Float = 0
    var peak: Float = 0
    var peakTimer: Int = 0
}
