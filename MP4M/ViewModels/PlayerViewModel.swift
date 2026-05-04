import Foundation
import Observation

/// 再生状態を管理する ViewModel
/// UI からの操作を受け付け、AudioEngineService を制御する
@Observable
final class PlayerViewModel: @unchecked Sendable {
    // MARK: - 表示状態

    var status: PlayStatus = .stopped
    var title: String = ""
    var pdxFileName: String = ""
    var currentTimeMs: Int = 0
    var totalTimeMs: Int = 0
    var loopCount: Int = 2 {
        didSet {
            UserDefaults.standard.set(loopCount, forKey: "mp4m_loopCount")
        }
    }
    var autoMode: AutoMode = .normal {
        didSet {
            UserDefaults.standard.set(autoMode.rawValue, forKey: "mp4m_autoMode")
        }
    }
    var repeatEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(repeatEnabled, forKey: "mp4m_repeatEnabled")
        }
    }

    var channels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: 16)
    var spectrumBars: [SpectrumBarState] = Array(repeating: SpectrumBarState(), count: 52)
    var mutedChannels: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(mutedChannels), forKey: "mp4m_mutedChannels")
        }
    }

    // MARK: - 内部

    private let audioService: any AudioEngineService
    private var displayTimer: Timer?
    private var fadeOutTimer: Timer?
    private var fadeOutVolume: Float = 1.0
    weak var browserVM: FileBrowserViewModel?
    private let metalCompute: MetalSpectrumCompute?

    // チャンネル状態キャッシング（優先度3: CPU 負荷低減）
    private var lastChannelStateUpdateMs: Int = 0
    private var cachedChannels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: 16)
    private let channelStateUpdateIntervalMs: Int = 100  // 100ms ごとにのみ取得

    // 再生時間計測（案C: C++ 呼び出し削減）
    private var playStartTimeMs: Int = 0          // 再生開始時の絶対時間
    private var playStartDate: Date = Date()      // 再生開始時刻
    private var lastSyncTimeMs: Int = 0           // 最後に同期した時刻
    private var lastSyncDate: Date = Date()       // 最後に同期した時刻（Date）
    private let syncIntervalMs: Int = 1000        // 1秒ごとに同期して誤差補正

    // スペアナ計算用バッファ
    private var speaBF1 = [Float](repeating: 0, count: 52)
    private let routeTable: [Float] = [
        0, 1, 4, 9, 16, 24, 35, 47, 61, 77, 94,
        113, 133, 155, 179, 204, 230, 258, 287, 317, 348,
        381, 415, 450, 486, 523, 561, 600, Float.greatestFiniteMagnitude
    ]
    private let riseTable: [Int] = [1, 1, 2, 2, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8, 8,
                                     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]

    // MARK: - 初期化

    init(audioService: any AudioEngineService) {
        print("[PlayerViewModel.init] START")
        self.audioService = audioService
        self.metalCompute = MetalSpectrumCompute()

        // UserDefaults から設定を復帰
        if let savedLoopCount = UserDefaults.standard.object(forKey: "mp4m_loopCount") as? Int {
            loopCount = savedLoopCount
        }
        if let savedAutoModeRaw = UserDefaults.standard.string(forKey: "mp4m_autoMode"),
           let savedAutoMode = AutoMode(rawValue: savedAutoModeRaw) {
            autoMode = savedAutoMode
        }
        if UserDefaults.standard.object(forKey: "mp4m_repeatEnabled") != nil {
            repeatEnabled = UserDefaults.standard.bool(forKey: "mp4m_repeatEnabled")
        }
        if let savedMutedChannels = UserDefaults.standard.array(forKey: "mp4m_mutedChannels") as? [Int] {
            mutedChannels = Set(savedMutedChannels)
        }

        print("[PlayerViewModel.init] calling audioService.start()")
        audioService.start(sampleRate: 44100)
        print("[PlayerViewModel.init] audioService.start() done")
    }

    /// 明示的クリーンアップ (deinit ではなく View の onDisappear で呼ぶ)
    func cleanup() {
        displayTimer?.invalidate()
        displayTimer = nil
        audioService.end()
    }

    // MARK: - 公開 API

    func load(url: URL) async {
        stop()
        mutedChannels = []

        // キャッシュをリセット
        lastChannelStateUpdateMs = 0
        cachedChannels = Array(repeating: ChannelDisplayState(), count: 16)

        // 最初に "No PDX" を設定（PDX未指定や読み込み失敗時に使用）
        pdxFileName = "No PDX"

    let loadedTitle = await Task.detached(priority: .userInitiated) { [weak self] in
        self?.audioService.loadMDXFile(path: url.path)
    }.value

        title = loadedTitle ?? url.deletingPathExtension().lastPathComponent

        // PDX ファイル名を audioService から取得（"no pdx" を含む場合は統一）
        if let pdxName = audioService.pdxFileName() {
            if pdxName.lowercased().contains("no pdx") {
                pdxFileName = "No PDX"
            } else {
                pdxFileName = pdxName
            }
        } else {
            pdxFileName = "No PDX"
        }

        currentTimeMs = 0
        totalTimeMs = 0
    }

    func play() {
        guard status != .playing else { return }

        let isPaused = (status == .paused)
        if isPaused {
            audioService.resume()
        } else {
            totalTimeMs = audioService.playWithLoopCount(Int32(loopCount))
        }

        audioService.startEngine()

        // 案C: 再生時間計測の初期化（毎フレーム C++ 呼び出しを削減）
        playStartTimeMs = audioService.currentPlayTimeMs()  // 初回のみ C++ 呼び出し
        playStartDate = Date()
        lastSyncTimeMs = playStartTimeMs
        lastSyncDate = Date()

        status = .playing
        startDisplayTimer()
    }

    func pause() {
        guard status == .playing else { return }
        audioService.pause()
        status = .paused
        displayTimer?.invalidate()
    }

    func stop() {
        audioService.stop()
        displayTimer?.invalidate()
        status = .stopped
        currentTimeMs = 0
        clearVisualState()
    }

    func togglePlay() {
        switch status {
        case .stopped: play()
        case .playing: pause()
        case .paused:  play()
        }
    }

    func setLoopCount(_ count: Int) {
        loopCount = max(0, min(9, count))
    }

    func setAutoMode(_ mode: AutoMode) {
        autoMode = mode
    }

    func toggleRepeat() {
        repeatEnabled.toggle()
    }

    func toggleChannel(_ channelIndex: Int) {
        let isMuted = mutedChannels.contains(channelIndex)
        if isMuted {
            mutedChannels.remove(channelIndex)
            audioService.setChannelMute(channelIndex, isMuted: false)
        } else {
            mutedChannels.insert(channelIndex)
            audioService.setChannelMute(channelIndex, isMuted: true)
        }
    }

    // MARK: - 次の曲・前の曲 (ファイルリストは外部から注入)

    func nextFileIndex(fileItems: [FileItem], playingIndex: Int) -> Int? {
        let files = fileItems.filter { !$0.isDirectory }
        guard !files.isEmpty else { return nil }

        var nextIndex = playingIndex + 1
        if autoMode == .shuffle {
            nextIndex = Int.random(in: 0..<files.count)
        }
        if nextIndex >= files.count { nextIndex = 0 }
        return nextIndex
    }

    func prevFileIndex(fileItems: [FileItem], playingIndex: Int) -> Int? {
        let files = fileItems.filter { !$0.isDirectory }
        guard !files.isEmpty else { return nil }

        var prevIndex = playingIndex - 1
        if prevIndex < 0 { prevIndex = files.count - 1 }
        return prevIndex
    }

    // MARK: - 表示更新タイマー (60fps)

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func updateDisplay() {
        guard status == .playing else { return }

        // DispatchQueue を使用してバックグラウンドで実行（優先度4: Task.detached より軽量）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 案C: ローカル時間計測（毎フレーム C++ 呼び出しを削減）
            let elapsedMs = Int((Date().timeIntervalSince(self.playStartDate)) * 1000)
            var ms = self.playStartTimeMs + elapsedMs

            // 1秒ごとに C++ 呼び出しで同期（ずれ補正）
            if abs(ms - self.lastSyncTimeMs) >= self.syncIntervalMs {
                ms = self.audioService.currentPlayTimeMs()
                self.playStartDate = Date()
                self.playStartTimeMs = ms
                self.lastSyncTimeMs = ms
                self.lastSyncDate = Date()
            }

            // 優先度3: チャンネル状態を 50ms ごとにのみ更新
            var fmChannels = self.cachedChannels
            if (ms - self.lastChannelStateUpdateMs) >= self.channelStateUpdateIntervalMs {
                fmChannels = self.audioService.getChannelStates()
                self.cachedChannels = fmChannels
                self.lastChannelStateUpdateMs = ms
            }

            let newBars = self.computeSpectrum(for: fmChannels)

            // メインスレッドで UI 更新
            DispatchQueue.main.async {
                self.currentTimeMs = ms
                self.channels = fmChannels
                self.spectrumBars = newBars

                // 再生時間が総時間に到達したら曲終了
                if self.totalTimeMs > 0 && self.currentTimeMs >= self.totalTimeMs {
                    self.handleTrackEnd()
                }
            }
        }
    }

    // MARK: - スペアナ計算

    private func computeSpectrum(for channels: [ChannelDisplayState]) -> [SpectrumBarState] {
        // GPU または CPU でビンマッピング + 拡散を計算
        let speaBuf = metalCompute?.computeSpectrum(channels: channels) ?? [Float](repeating: 0, count: 52)

        // 3. バー状態更新
        var newBars = spectrumBars
        let maxBars = Float(routeTable.count - 1)
        for i in 0..<32 {
            var bar = newBars[i]
            let raw = speaBuf[i + 5]
            var targetBar: Float = 0

            if raw > 0 {
                for j in 0..<routeTable.count {
                    if raw < routeTable[j] {
                        if bar.current < Float(j) { targetBar = Float(j) }
                        break
                    }
                }
            }

            if targetBar > bar.current {
                let diff = Int(targetBar - bar.current)
                let rise = Float(diff < riseTable.count ? riseTable[diff] : 8)
                bar.current = min(bar.current + rise, maxBars)
            } else if targetBar < bar.current {
                let diff = bar.current - targetBar
                bar.current -= (diff > 2) ? 2 : diff
            }

            if bar.peakTimer > 0 { bar.peakTimer -= 1 }
            if bar.peakTimer == 0, bar.peak > 0 { bar.peak -= 1 }
            if bar.peak < targetBar {
                bar.peak = targetBar
                bar.peakTimer = 10
            }
            newBars[i] = bar
        }

        return newBars
    }

    // MARK: - 曲終了ハンドリング

    private func handleTrackEnd() {
        guard status == .playing else { return }

        // 重複呼び出し防止：一度停止状態に変更
        status = .stopped
        displayTimer?.invalidate()

        print("[TrackEnd] repeatEnabled=\(repeatEnabled)")
        if repeatEnabled {
            audioService.stop()
            play()
        } else {
            // フェードアウト処理を開始
            startFadeOut()
        }
    }

    private func startFadeOut() {
        print("[FadeOut] Starting fadeout")
        fadeOutVolume = 1.0
        let fadeOutDuration = 3.0 // 3秒で完全に無音になるまでフェードアウト
        let fadeOutInterval = 0.05 // 50ms ごとに音量を更新
        let fadeOutSteps = Int(fadeOutDuration / fadeOutInterval)
        print("[FadeOut] fadeOutSteps=\(fadeOutSteps), decrement=\(1.0 / Float(fadeOutSteps))")

        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: fadeOutInterval, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.fadeOutVolume -= 1.0 / Float(fadeOutSteps)
            self.audioService.setVolume(max(0.0, self.fadeOutVolume))
            if self.fadeOutVolume.truncatingRemainder(dividingBy: 0.2) < 0.01 {
                print("[FadeOut] fadeOutVolume=\(String(format: "%.2f", self.fadeOutVolume))")
            }
            if self.fadeOutVolume <= 0.0 {
                print("[FadeOut] Complete (fadeOutVolume=\(String(format: "%.2f", self.fadeOutVolume))), playing next track")
                timer.invalidate()
                self.fadeOutTimer = nil
                self.fadeOutVolume = 1.0
                self.audioService.setVolume(1.0)
                self.playNextTrack()
            }
        }
    }

    private func playNextTrack() {
        print("[NextTrack] Starting next track")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let browserVM = self.browserVM else {
                print("[NextTrack] browserVM is nil, stopping")
                self?.stop()
                return
            }

            let files = browserVM.fileItems.filter { !$0.isDirectory }
            guard !files.isEmpty else {
                print("[NextTrack] No files, stopping")
                self.stop()
                return
            }

            if let nextIdx = self.nextFileIndex(fileItems: browserVM.fileItems, playingIndex: browserVM.playingIndex) {
                print("[NextTrack] Playing next file at index \(nextIdx)")
                browserVM.playingIndex = nextIdx
                Task {
                    await self.load(url: files[nextIdx].url)
                    self.play()
                }
            } else {
                print("[NextTrack] No next file, stopping")
                self.stop()
            }
        }
    }

    private func clearVisualState() {
        channels = Array(repeating: ChannelDisplayState(), count: 16)
        spectrumBars = Array(repeating: SpectrumBarState(), count: 52)
    }
}
