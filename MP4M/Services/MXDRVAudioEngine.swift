import AVFoundation
import Foundation

/// MXDRVGBridge + AVAudioEngine を組み合わせたオーディオエンジン実装
final class MXDRVAudioEngine: AudioEngineService {
    private let sampleRate: Int = 44100
    private var engine = AVAudioEngine()
    private var node: AVAudioSourceNode?

    // オーディオスレッド用バッファ
    private static let maxFrameCount = 1024
    private static let pcmBufferSize = maxFrameCount * 2
    nonisolated(unsafe) private var pcmBuffer: [Int16] = [Int16](repeating: 0, count: pcmBufferSize)

    init() {
        fputs("[MXDRVAudioEngine.init]\n", stderr)
    }

    var sourceNode: AVAudioSourceNode? { node }

    func start(sampleRate: Int32) {
        MXDRVGBridge.start(withSampleRate: sampleRate)
        setupAudioEngine()
    }

    func end() {
        engine.stop()
        MXDRVGBridge.end()
    }

    func loadMDXFile(path: String) -> String? {
        MXDRVGBridge.loadMDXFile(path)
    }

    func pdxFileName() -> String? {
        MXDRVGBridge.pdxFileName()
    }

    func playWithLoopCount(_ loopCount: Int32) -> Int {
        MXDRVGBridge.play(withLoopCount: loopCount)
        return Int(MXDRVGBridge.totalPlayTimeMs())
    }

    func stop() {
        MXDRVGBridge.stop()
        engine.stop()
    }

    func pause() {
        MXDRVGBridge.pause()
    }

    func resume() {
        MXDRVGBridge.resume()
    }

    func isTerminated() -> Bool {
        return MXDRVGBridge.isTerminated()
    }

    func currentPlayTimeMs() -> Int {
        return Int(MXDRVGBridge.currentPlayTimeMs())
    }

    func getChannelStates() -> [ChannelDisplayState] {
        var raw = [MP4MChannelState](repeating: MP4MChannelState(), count: 16)
        MXDRVGBridge.getChannelStates(&raw)

        return (0..<16).map { i in
            ChannelDisplayState(
                keyCode:   raw[i].keyCode,
                velocity:  raw[i].velocity,
                keyOn:     raw[i].keyOn != 0,
                volume:    raw[i].volume,
                bend:      raw[i].bend,
                pan:       raw[i].pan,
                keyOffset: raw[i].keyOffset
            )
        }
    }

    func renderPCM(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int32) -> Int32 {
        return MXDRVGBridge.getPCM(buffer, frameCount: frameCount)
    }

    func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("[MXDRVAudioEngine] start failed: \(error)")
        }
    }

    private func setupAudioEngine() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 2,
            interleaved: false
        )!

        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            self?.renderAudioCallback(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        node = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    private func renderAudioCallback(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard ablPointer.count >= 2,
              let leftPtr  = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
              let rightPtr = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
        else { return }

        guard frameCount <= Self.maxFrameCount,
              frameCount * 2 <= Self.pcmBufferSize
        else { return }

        let ret = renderPCM(into: &pcmBuffer, frameCount: Int32(frameCount))
        guard ret > 0 else { return }

        for i in 0..<frameCount {
            leftPtr[i]  = Float(pcmBuffer[i * 2])     / 32768.0
            rightPtr[i] = Float(pcmBuffer[i * 2 + 1]) / 32768.0
        }
    }
}
