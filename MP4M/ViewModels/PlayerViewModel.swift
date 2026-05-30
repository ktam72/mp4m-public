import Foundation
import Observation

/// 再生状態を管理する ViewModel
///
/// UI からの操作を受け付け、各サービスに処理を委譲する。
/// 表示更新ループ・トラック遷移は専用マネージャに分離。
@MainActor
@Observable
final class PlayerViewModel {
    // MARK: - 表示状態

    var status: PlayStatus = .stopped
    var title: String = ""
    var pdxFileName: String = ""
    var currentTimeMs: Int = 0
    var totalTimeMs: Int = 0
    var loopCount: Int = 2 {
        didSet { UserDefaults.standard.set(loopCount, forKey: UserDefaultsKey.loopCount) }
    }
    var autoMode: AutoMode = .normal {
        didSet {
            UserDefaults.standard.set(autoMode.rawValue, forKey: UserDefaultsKey.autoMode)
            transitionManager.autoMode = autoMode
        }
    }

    var channels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
    var spectrumBars: [SpectrumBarState] = Array(repeating: SpectrumBarState(), count: AudioConstants.spectrumBinCount)
    var mutedChannels: Set<Int> = [] {
        didSet { UserDefaults.standard.set(Array(mutedChannels), forKey: UserDefaultsKey.mutedChannels) }
    }

    /// 現在のエラー状態（nil でエラーなし）
    var currentError: MP4MError?

    // MARK: - 内部依存

    private let audioService: any AudioEngineService
    private let spectrumService: SpectrumComputeService
    private let channelService: ChannelStateService
    private let displayManager: DisplayUpdateManager
    private let transitionManager: TrackTransitionManager
    weak var browserVM: FileBrowserViewModel? {
        didSet { transitionManager.browserVM = browserVM }
    }

    // 再生時間計測（案C: C++ 呼び出し削減）
    private var playStartTimeMs: Int = 0
    private var playStartDate: Date = Date()
    private var lastSyncTimeMs: Int = 0
    private var lastSyncDate: Date = Date()
    private let syncIntervalMs: Int = 1000

    // MARK: - 初期化

    init(audioService: any AudioEngineService) {
        Log.debug("[PlayerViewModel.init] START")
        self.audioService = audioService
        self.spectrumService = SpectrumComputeService()
        self.channelService = ChannelStateService(audioService: audioService)
        self.displayManager = DisplayUpdateManager()
        self.transitionManager = TrackTransitionManager()

        transitionManager.delegate = self

        // UserDefaults から設定を復帰
        if let savedLoopCount = UserDefaults.standard.object(forKey: UserDefaultsKey.loopCount) as? Int {
            loopCount = savedLoopCount
        }
        if let savedAutoModeRaw = UserDefaults.standard.string(forKey: UserDefaultsKey.autoMode),
           let savedAutoMode = AutoMode(rawValue: savedAutoModeRaw) {
            autoMode = savedAutoMode
        }
        if let savedMutedChannels = UserDefaults.standard.array(forKey: UserDefaultsKey.mutedChannels) as? [Int] {
            mutedChannels = Set(savedMutedChannels)
        }

        Log.debug("[PlayerViewModel.init] calling audioService.start()")
        audioService.start(sampleRate: 44100)
        Log.debug("[PlayerViewModel.init] audioService.start() done")
    }

    /// 明示的クリーンアップ (deinit ではなく View の onDisappear で呼ぶ)
    func cleanup() {
        displayManager.stop()
        transitionManager.cancelFadeOut()
        audioService.setVolume(1.0)
        audioService.end()
    }

    // MARK: - 公開 API

    /// MDX ファイルをロードし、タイトルと PDX 情報を設定
    func load(url: URL) async {
        Log.debug("[PlayerVM.load] START url=\(url.path)")
        stop()
        mutedChannels = []
        channelService.resetCache()
        currentError = nil

        do {
            let loadedTitle = try audioService.loadMDXFile(path: url.path)

            title = loadedTitle ?? url.deletingPathExtension().lastPathComponent
            pdxFileName = audioService.pdxFileName() ?? "No PDX"

            if let pdxError = audioService.pdxLoadError() {
                Log.debug("[PlayerVM.load] PDX load error: \(pdxError.errorDescription ?? "unknown")")
                currentError = pdxError
            }

            currentTimeMs = 0
            totalTimeMs = 0
            Log.debug("[PlayerVM.load] SUCCESS title=\(title) pdxFileName=\(pdxFileName)")
        } catch let error as MP4MError {
            currentError = error
            title = url.deletingPathExtension().lastPathComponent
            pdxFileName = "No PDX"
            currentTimeMs = 0
            totalTimeMs = 0
            Log.debug("[PlayerVM.load] MP4MError: \(error.errorDescription ?? "unknown")")
        } catch {
            currentError = MP4MError.mdxLoadFailed(error.localizedDescription)
            title = url.deletingPathExtension().lastPathComponent
            pdxFileName = "No PDX"
            currentTimeMs = 0
            totalTimeMs = 0
            Log.debug("[PlayerVM.load] Error: \(error.localizedDescription)")
        }
    }

    /// 再生開始・再開
    func play() {
        guard status != .playing else { return }

        let isPaused = (status == .paused)
        if isPaused {
            audioService.resume()
        } else {
            totalTimeMs = audioService.playWithLoopCount(Int32(loopCount))
        }

        startPlayback()
    }

    /// バックグラウンドで再生時間を計測してから再生開始
    func playAsync() async {
        Log.debug("[PlayerVM.playAsync] START status=\(status) loopCount=\(loopCount)")
        guard status != .playing else {
            Log.debug("[PlayerVM.playAsync] already playing, skipping")
            return
        }

        let isPaused = (status == .paused)
        if isPaused {
            audioService.resume()
        } else {
            print("[PlayerViewModel] playAsync - Starting new playback")
            totalTimeMs = audioService.playWithLoopCount(Int32(loopCount))
            print("[PlayerViewModel] playAsync - playWithLoopCount done, totalTimeMs: \(totalTimeMs)")
        }

        startPlayback()
        Log.debug("[PlayerVM.playAsync] playback started, status=\(status)")
    }

    /// 一時停止
    func pause() {
        guard status == .playing else { return }
        audioService.pause()
        status = .paused
        displayManager.stop()
    }

    /// 停止
    func stop() {
        audioService.stop()
        displayManager.stop()
        transitionManager.cancelFadeOut()
        status = .stopped
        currentTimeMs = 0
        clearVisualState()
    }

    /// 再生・一時停止をトグル切り替え
    func togglePlay() {
        switch status {
        case .stopped: play()
        case .playing: pause()
        case .paused:  play()
        }
    }

    /// ループ回数を設定（0-9）
    func setLoopCount(_ count: Int) {
        loopCount = max(0, min(9, count))
    }

    /// 自動再生モードを設定
    func setAutoMode(_ mode: AutoMode) {
        autoMode = mode
    }

    /// OPM エンジンを切り替え（AboutView からの呼び出し用）
    /// 再生時間計測（MeasurePlayTime）はバックグラウンドで実行しメインスレッドをブロックしない
    func setOpmEngine(_ type: Int) {
        Task.detached(priority: .userInitiated) {
            MXDRVGBridge.setOpmEngine(Int32(type))

            await MainActor.run {
                self.totalTimeMs = Int(MXDRVGBridge.totalPlayTimeMs())
                self.playStartTimeMs = 0
                self.playStartDate = Date()
                self.lastSyncTimeMs = 0
                self.lastSyncDate = Date()
            }
        }
    }

    /// チャンネルのミュートをトグル切り替え
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

    // MARK: - 次の曲・前の曲

    func playNextFile(browserVM: FileBrowserViewModel) {
        transitionManager.playNextFile(browserVM: browserVM)
    }

    func playPrevFile(browserVM: FileBrowserViewModel) {
        transitionManager.playPrevFile(browserVM: browserVM)
    }

    // MARK: - 表示更新タイマー

    private func startPlayback() {
        Log.debug("[PlayerVM] startPlayback - START")
        do {
            try audioService.startEngine()
            Log.debug("[PlayerVM] startEngine succeeded")
        } catch let error as MP4MError {
            Log.debug("[PlayerVM] startEngine MP4MError: \(error.errorDescription ?? "unknown")")
            currentError = error
            return
        } catch {
            Log.debug("[PlayerVM] startEngine error: \(error.localizedDescription)")
            currentError = MP4MError.audioEngineFailed(error.localizedDescription)
            return
        }

        playStartTimeMs = audioService.currentPlayTimeMs()
        playStartDate = Date()
        lastSyncTimeMs = playStartTimeMs
        lastSyncDate = Date()
        Log.debug("[PlayerVM] startPlayback - playStartTimeMs: \(playStartTimeMs)")

        status = .playing
        displayManager.resetFrameCount()
        displayManager.start(
            shouldContinue: { [weak self] in
                guard let self else { return false }
                return status == .playing || transitionManager.isFadingOut
            },
            update: { [weak self] frameCount in
                self?.updateDisplay(frameCount: frameCount)
            }
        )
        Log.debug("[PlayerVM] status set to .playing, display timer started")
    }

    private func updateDisplay(frameCount: Int) {
        // 再生時間計算
        var ms = playStartTimeMs + Int(Date().timeIntervalSince(playStartDate) * 1000)

        if abs(ms - lastSyncTimeMs) >= syncIntervalMs {
            ms = audioService.currentPlayTimeMs()
            playStartDate = Date()
            playStartTimeMs = ms
            lastSyncTimeMs = ms
            lastSyncDate = Date()
        }

        if frameCount > 0 && frameCount % AudioConstants.frameRate == 0 {
            Log.debug("[PlayerVM] updateDisplay - frame: \(frameCount), currentTimeMs: \(ms)")
        }

        // チャンネル状態の取得（キーボード・レベルメーター: 毎フレーム 120fps）
        let fmChannels = channelService.getChannels(currentTimeMs: ms)

        // スペアナ計算は 60fps（2フレームごと）
        let shouldUpdateSpectrum = (frameCount % 2) == 0
        if shouldUpdateSpectrum {
            let newBars = spectrumService.computeSpectrum(for: fmChannels, currentBars: spectrumBars)
            currentTimeMs = ms
            if newBars != spectrumBars {
                spectrumBars = newBars
            }

            if totalTimeMs > 0 && currentTimeMs >= totalTimeMs {
                transitionManager.handleTrackEnd()
            }
        }

        if fmChannels != channels {
            channels = fmChannels
        }
    }

    // MARK: - 内部

    private func clearVisualState() {
        channels = Array(repeating: ChannelDisplayState(), count: AudioConstants.channelCount)
        spectrumBars = Array(repeating: SpectrumBarState(), count: AudioConstants.spectrumBinCount)
    }
}

// MARK: - TrackTransitionManagerDelegate

extension PlayerViewModel: TrackTransitionManagerDelegate {
    func loadAndPlay(url: URL) async {
        await load(url: url)
        play()
    }

    func stopPlayback() {
        stop()
    }

    func setAudioVolume(_ volume: Float) {
        audioService.setVolume(volume)
    }
}
