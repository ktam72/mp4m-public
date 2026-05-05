import Foundation
import SwiftUI

// MARK: - 再生状態

/// 再生状態を表す列挙
enum PlayStatus: Equatable {
    /// 停止中
    case stopped
    /// 再生中
    case playing
    /// 一時停止中
    case paused
}

/// 自動再生モードを表す列挙
enum AutoMode: String, CaseIterable {
    /// 通常モード（設定したループ回数のみ再生）
    case normal  = "NORMAL"
    /// オートモード（設定したループ回数を再生後、次の曲へ）
    case auto    = "AUTO"
    /// シャッフルモード（ランダムに次の曲を選択）
    case shuffle = "SHUFFLE"
}

// MARK: - チャンネル表示データ

/// FM/PCM チャンネルの表示用状態
/// MXDRVG エンジンから取得した生データを UI 表示用にラップした構造体
struct ChannelDisplayState {
    /// YM2151 KC レジスタ値（キーコード、上位3ビット=オクターブ、下位4ビット=ノート）
    var keyCode: UInt8 = 0
    /// ベロシティ（鍵盤の押し込み強さ、0-127）
    var velocity: UInt8 = 0
    /// キーオン状態（true で発音中）
    var keyOn: Bool = false
    /// 音量（0-127、スペアナ計算やレベルメーター表示に使用）
    var volume: UInt8 = 0
    /// ピッチベンド値（未使用）
    var bend: Int16 = 0
    /// パン設定（0=L、1=C、2=R、3=LR）
    var pan: UInt8 = 1
    /// キーオフセット（未使用）
    var keyOffset: UInt8 = 0
}

// MARK: - ChannelDisplayState 拡張（表示ロジック）
extension ChannelDisplayState {
    /// PAN 表示用文字列を返す（L:左、C:中央、R:右、LR:ステレオ）
    ///
    /// - Parameters:
    ///   - isPCMChannel: PCMチャンネル（index 8-15）の場合はtrue、FMチャンネル（index 0-7）の場合はfalse
    /// - Returns: 表示用文字列（L/C/R/LR、非アクティブ時は空文字）
    /// - Note: PCMチャンネルでpan=3（ステレオ）の場合、強制的に"C"を返す（元の実装仕様に準拠）
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

    /// PAN値に対応する表示色を返す
    ///
    /// - Returns: 表示用Color（L:シアン系、C:明るい白、R:琥珀色、非アクティブ時はclear）
    /// - Note: 色の不透明度は0.8に固定
    var displayPanColor: Color {
        guard keyOn else { return .clear }
        switch pan {
        case 0: return Color.mp4mCyan.opacity(0.8)
        case 2: return Color.mp4mAmber.opacity(0.8)
        default: return Color.mp4mBright.opacity(0.8)
        }
    }

    /// チャンネルの正規化レベル（0.0〜1.0）を返す
    ///
    /// - Returns: 0.0（無音）〜1.0（最大音量）のCGFloat値
    /// - Note: 計算式は min(volume / 15.0, 1.0) で、非アクティブ時は0.0
    var displayLevel: CGFloat {
        guard keyOn else { return 0 }
        return min(CGFloat(volume) / 15.0, 1.0)
    }

    /// チャンネルがアクティブ（発音中）かどうかを返す
    ///
    /// - Returns: keyOnがtrueの場合はtrue、それ以外はfalse
    var isActive: Bool { keyOn }
}

// MARK: - スペアナバー状態

/// スペアナの各バー（周波数ビン）の状態
/// メーターの現在値・ピーク値・ピーク保持タイマーを保持
struct SpectrumBarState {
    /// 現在のバー高さ（0.0〜28.0、routeTableのインデックス）
    var current: Float = 0
    /// ピーク値（現在値の最大値、0.0〜28.0）
    var peak: Float = 0
    /// ピーク保持タイマー（0になるまでピークを保持、その後1ずつ減少）
    var peakTimer: Int = 0
}
