import Foundation

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
    /// ランダムモード（ランダムに次の曲を選択）
    case random  = "RANDOM"
}

// MARK: - チャンネル表示データ

/// FM/PCM チャンネルの表示用状態
/// MXDRVG エンジンから取得した生データを UI 表示用にラップした構造体
struct ChannelDisplayState: Equatable {
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



// MARK: - ChannelDisplayState 拡張（表示ロジック、View非依存のもののみ）

extension ChannelDisplayState {
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

    var displayLevel: CGFloat {
        guard keyOn else { return 0 }
        return min(CGFloat(volume) / 15.0, 1.0)
    }
}

// MARK: - スペアナバー状態

/// スペアナの各バー（周波数ビン）の状態
/// メーターの現在値・ピーク値・ピーク保持タイマーを保持
struct SpectrumBarState: Equatable {
    /// 現在のバー高さ（0.0〜28.0、routeTableのインデックス）
    var current: Float = 0
    /// ピーク値（現在値の最大値、0.0〜28.0）
    var peak: Float = 0
    /// ピーク保持タイマー（0になるまでピークを保持、その後1ずつ減少）
    var peakTimer: Int = 0
}
