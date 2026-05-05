import AVFoundation
import Foundation

/// オーディオエンジンサービスのプロトコル
/// テスト用にモック化可能
protocol AudioEngineService: AnyObject {
    /// 初期化 (サンプリングレート設定)
    func start(sampleRate: Int32)

    /// 終了・メモリ解放
    func end()

    /// MDX ファイル読み込み
    /// - Parameter path: ファイルパス
    /// - Returns: タイトル文字列 (nil で失敗)
    /// - Throws: MP4MError で失敗理由を通知
    func loadMDXFile(path: String) throws -> String?

    /// ロード済み PDX ファイル名
    func pdxFileName() -> String?

    /// PDX ロード失敗時のエラー (nil でエラーなし)
    func pdxLoadError() -> MP4MError?

    /// 再生開始 (ループ回数指定)
    /// - Parameter loopCount: ループ回数
    /// - Returns: 総再生時間 (ミリ秒)
    func playWithLoopCount(_ loopCount: Int32) -> Int

    /// 停止
    func stop()

    /// 一時停止
    func pause()

    /// 再開
    func resume()

    /// 演奏終了フラグ
    func isTerminated() -> Bool

    /// 現在再生位置 (ミリ秒)
    func currentPlayTimeMs() -> Int

    /// チャンネル状態取得
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
    func startEngine() throws

    /// 音量設定 (0.0〜1.0)
    func setVolume(_ volume: Float)

    /// ミュート対象チャンネルを設定
    func setMutedChannels(_ mutedChannels: Set<Int>)

    /// チャンネルミュート制御 (出力レベル制御)
    func setChannelMute(_ ch: Int, isMuted: Bool)
}
