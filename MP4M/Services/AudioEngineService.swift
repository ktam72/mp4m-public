import AVFoundation
import Foundation

/// オーディオエンジンサービスのプロトコル
/// テスト用にモック化可能
protocol AudioEngineService: AnyObject {
    /// 初期化 (サンプリングレート設定)
    /// - Parameter sampleRate: サンプリングレート (例: 44100)
    func start(sampleRate: Int32)

    /// 終了・メモリ解放
    func end()

    /// MDX ファイル読み込み
    /// - Parameter path: ファイルパス
    /// - Throws: MP4MError で失敗理由を通知 (ファイル不存在・破損等)
    /// - Returns: タイトル文字列 (nil で失敗)
    func loadMDXFile(path: String) throws -> String?

    /// ロード済み PDX ファイル名
    /// - Returns: PDX ファイル名、未設定時は nil
    func pdxFileName() -> String?

    /// PDX ロード失敗時のエラー
    /// - Returns: エラーがあれば MP4MError、なければ nil
    func pdxLoadError() -> MP4MError?

    /// 再生開始 (ループ回数指定)
    /// - Parameter loopCount: ループ回数
    /// - Returns: 総再生時間 (ミリ秒、0 は未設定)
    func playWithLoopCount(_ loopCount: Int32) -> Int

    /// 停止
    func stop()

    /// 一時停止
    func pause()

    /// 再開
    func resume()

    /// 演奏終了フラグ
    /// - Returns: 演奏が終了している場合は true
    func isTerminated() -> Bool

    /// 現在再生位置 (ミリ秒)
    /// - Returns: 現在の再生位置 (ms)
    func currentPlayTimeMs() -> Int

    /// チャンネル状態取得 (排他制御付き)
    /// - Returns: 16チャンネル分の表示状態
    /// - Note: 内部で os_unfair_lock による排他制御を行う
    func getChannelStates() -> [ChannelDisplayState]

    /// PCM レンダーコールバック用
    /// - Parameters:
    ///   - buffer: Int16 バッファ (最大 2048 要素)
    ///   - frameCount: フレーム数
    /// - Returns: 生成されたフレーム数
    func renderPCM(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int32) -> Int32

    /// AVAudioEngine のソースノードを提供
    var sourceNode: AVAudioSourceNode? { get }

    /// AVAudioEngine 開始
    /// - Throws: MP4MError.audioEngineFailed で失敗理由を通知
    func startEngine() throws

    /// 音量設定 (0.0〜1.0)
    /// - Parameter volume: 設定する音量 (0.0=無音、1.0=最大)
    func setVolume(_ volume: Float)

    /// チャンネルミュート制御 (出力レベル制御)
    /// - Parameters:
    ///   - ch: チャンネル番号 (0-15)
    ///   - isMuted: true でミュート、false で解除
    func setChannelMute(_ ch: Int, isMuted: Bool)
}
