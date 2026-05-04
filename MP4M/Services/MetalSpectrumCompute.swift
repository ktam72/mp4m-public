import Metal
import MetalKit

final class MetalSpectrumCompute {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?
    private let channelBuffer: MTLBuffer?
    private let speaBuffer: MTLBuffer?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[Metal] MTLDevice not available")
            self.device = nil
            self.commandQueue = nil
            self.pipelineState = nil
            self.channelBuffer = nil
            self.speaBuffer = nil
            return nil
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        guard let library = device.makeDefaultLibrary() else {
            print("[Metal] Failed to load default library (Spectrum.metal)")
            self.pipelineState = nil
            self.channelBuffer = nil
            self.speaBuffer = nil
            return nil
        }

        guard let function = library.makeFunction(name: "computeSpectrum") else {
            print("[Metal] Function 'computeSpectrum' not found")
            self.pipelineState = nil
            self.channelBuffer = nil
            self.speaBuffer = nil
            return nil
        }

        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("[Metal] Failed to create compute pipeline: \(error)")
            self.pipelineState = nil
            self.channelBuffer = nil
            self.speaBuffer = nil
            return nil
        }

        // バッファ確保（16チャンネル + 52ビン）
        self.channelBuffer = device.makeBuffer(length: 16 * 8, options: .storageModeShared)
        self.speaBuffer = device.makeBuffer(length: 52 * MemoryLayout<Float>.size, options: .storageModeShared)

        print("[Metal] GPU compute initialized successfully")
    }

    func computeSpectrum(channels: [ChannelDisplayState]) -> [Float] {
        guard let device = device,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let channelBuffer = channelBuffer,
              let speaBuffer = speaBuffer else {
            return [Float](repeating: 0, count: 52)
        }

        // チャンネルデータを GPU バッファに転送
        let contents = channelBuffer.contents()
        var channelData = [UInt8](repeating: 0, count: 16 * 8)
        for i in 0..<min(16, channels.count) {
            let ch = channels[i]
            channelData[i * 8 + 0] = ch.keyCode
            channelData[i * 8 + 1] = ch.keyOffset
            channelData[i * 8 + 2] = ch.velocity
            channelData[i * 8 + 3] = ch.keyOn ? 1 : 0
        }
        memcpy(contents, &channelData, channelData.count)

        // speaBuf を 0 でクリア
        memset(speaBuffer.contents(), 0, 52 * MemoryLayout<Float>.size)

        // コマンドバッファ作成
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return [Float](repeating: 0, count: 52)
        }

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return [Float](repeating: 0, count: 52)
        }

        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(channelBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(speaBuffer, offset: 0, index: 1)

        // スレッドグループサイズ（最大 16 チャンネル）
        let threadGroupSize = MTLSize(width: 16, height: 1, depth: 1)
        let gridSize = MTLSize(width: 16, height: 1, depth: 1)

        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // 結果を読み込み
        let speaBufPtr = speaBuffer.contents().assumingMemoryBound(to: Float.self)
        var result = [Float](repeating: 0, count: 52)
        for i in 0..<52 {
            result[i] = speaBufPtr[i]
        }

        return result
    }
}
