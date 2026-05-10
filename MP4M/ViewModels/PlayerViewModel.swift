import Foundation
import Observation

/// 再生状態を管理する ViewModel
/// UI からの操作を受け付け、各サービスに処理を委譲する
///
/// エラーハンドリング・スペアナ計算・チャンネル状態取得を各サービスに分離し、保守性を向上
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
            UserDefaults.standard.set(loopCount, forKey: UserDefaultsKey.loopCount)
        }
    }
    var autoMode: AutoMode = .normal {
        didSet {
            UserDefaults.standard.set(autoMode.rawValue, forKey: UserDefaultsKey.autoMode)
        }
    }

    var channels: [ChannelDisplayState] = Array(repeating: ChannelDisplayState(), count: 16)
    var spectrumBars: [SpectrumBarState] = Array(repeating: SpectrumBarState(), count: 52)
    var mutedChannels: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(mutedChannels), forKey: UserDefaultsKey.mutedChannels)
        }
    }

    /// 現在のエラー状態（nil でエラーなし）
    /// - Note: エラー発生時に Alert で表示される
    var currentError: MP4MError?

    // MARK: - 内部

    private let audioService: any AudioEngineService
    private let spectrumService: SpectrumComputeService
    private let channelService: ChannelStateService
    private let displayService: DisplayUpdateService
    private var displayTask: Task<Void, Never>?
    private var fadeOutTask: Task<Void, Never>?
    private var fadeOutVolume: Float = 1.0
    weak var browserVM: FileBrowserViewModel?

    // 再生時間計測（案C: C++ 呼び出し削減）
    private var playStartTimeMs: Int = 0          // 再生開始時の絶対時間
    private var playStartDate: Date = Date()      // 再生開始時刻
    private var lastSyncTimeMs: Int = 0           // 最後に同期した時刻
    private var lastSyncDate: Date = Date()       // 最後に同期した時刻（Date）
    private let syncIntervalMs: Int = 1000        // 1秒ごとに同期して誤差補正

    // 表示更新頻度制御
    private var displayFrameCount: Int = 0        // フレームカウンタ（120fps基準）

    // MARK: - 初期化

    init(audioService: any AudioEngineService) {
        Log.debug("[PlayerViewModel.init] START")
        self.audioService = audioService
        self.spectrumService = SpectrumComputeService()
        self.channelService = ChannelStateService(audioService: audioService)
        self.displayService = DisplayUpdateService()

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
        displayTask?.cancel()
        displayTask = nil
        fadeOutTask?.cancel()
        fadeOutTask = nil
        audioService.setVolume(1.0)
        audioService.end()
    }

    // MARK: - 公開 API

    /// MDX ファイルをロードし、タイトルと PDX 情報を設定
    /// - Parameter url: ロードする MDX ファイルの URL
    /// - Note: エラー発生時は currentError に MP4MError を設定
    func load(url: URL) async {
        Log.debug("[PlayerVM.load] START url=\(url.path)")
        stop()
        mutedChannels = []
        channelService.resetCache()
        currentError = nil

        do {
            let loadedTitle = try await Task.detached(priority: .userInitiated) { [weak self] in
                try self?.audioService.loadMDXFile(path: url.path)
            }.value

            title = loadedTitle ?? url.deletingPathExtension().lastPathComponent

            // PDX ファイル名をオーディオサービスから取得（既にブリッジ側で正規化済み）
            pdxFileName = audioService.pdxFileName() ?? "No PDX"

            // PDX 読み込みエラーがあれば設定
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
    /// - Note: 既に再生中の場合は何もしない、一時停止中の場合は再開
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

    /// バックグラウンドで再生時間を計測してから再生開始（メインスレッドをブロックしない）
    func playAsync() async {
        Log.debug("[PlayerVM.playAsync] START status=\(status) loopCount=\(loopCount)")
        guard status != .playing else {
            Log.debug("[PlayerVM.playAsync] already playing, skipping")
            return
        }

        let isPaused = (status == .paused)
        if isPaused {
            Log.debug("[PlayerVM.playAsync] resuming from pause")
            audioService.resume()
        } else {
            print("[PlayerViewModel] playAsync - Starting new playback")
            totalTimeMs = await Task.detached(priority: .userInitiated) { [self] in
                Log.debug("[PlayerVM.playAsync] calling playWithLoopCount(\(loopCount))...")
                let result = audioService.playWithLoopCount(Int32(loopCount))
                Log.debug("[PlayerVM.playAsync] playWithLoopCount returned totalTimeMs=\(result)")
                return result
            }.value
            print("[PlayerViewModel] playAsync - playWithLoopCount done, totalTimeMs: \(totalTimeMs)")
        }

        await MainActor.run {
            startPlayback()
        }
        Log.debug("[PlayerVM.playAsync] playback started, status=\(status)")
    }

    /// play() / playAsync() 共通の再生開始処理
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

        // 案C: 再生時間計測の初期化
        playStartTimeMs = audioService.currentPlayTimeMs()
        playStartDate = Date()
        lastSyncTimeMs = playStartTimeMs
        lastSyncDate = Date()
        Log.debug("[PlayerVM] startPlayback - playStartTimeMs: \(playStartTimeMs)")

        status = .playing
        startDisplayUpdates()
        Log.debug("[PlayerVM] status set to .playing, display timer started")
    }

    /// 一時停止
    /// - Note: 再生中の場合のみ動作、タイマーを無効化
    func pause() {
        guard status == .playing else { return }
        audioService.pause()
        status = .paused
        displayTask?.cancel()
        displayTask = nil
    }

    /// 停止
    /// - Note: 再生中・一時停止中の場合に動作、表示状態をリセット
    func stop() {
        audioService.stop()
        displayTask?.cancel()
        displayTask = nil
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
    /// - Parameter count: 設定するループ回数
    func setLoopCount(_ count: Int) {
        loopCount = max(0, min(9, count))
    }

    /// 自動再生モードを設定
    /// - Parameter mode: 設定する AutoMode
    func setAutoMode(_ mode: AutoMode) {
        autoMode = mode
    }

    /// リピート再生の有効/無効をトグル切り替え
    /// チャンネルのミュートをトグル切り替え
    /// - Parameter channelIndex: 対象チャンネル番号 (0-15)
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

    /// 次の曲のファイルインデックスを取得
    /// - Parameters:
    ///   - playableFiles: 再生可能なファイル配列
    ///   - playingIndex: 現在再生中のインデックス
    /// - Returns: 次のインデックス（該当なしの場合は nil）
    func nextFileIndex(playableFiles: [FileItem], playingIndex: Int) -> Int? {
        guard !playableFiles.isEmpty else { return nil }

        var nextIndex = playingIndex + 1
        if autoMode == .random {
            nextIndex = Int.random(in: 0..<playableFiles.count)
        }
        if nextIndex >= playableFiles.count { nextIndex = 0 }
        return nextIndex
    }

    /// 前の曲のファイルインデックスを取得
    /// - Parameters:
    ///   - playableFiles: 再生可能なファイル配列
    ///   - playingIndex: 現在再生中のインデックス
    /// - Returns: 前のインデックス（該当なしの場合は nil）
    func prevFileIndex(playableFiles: [FileItem], playingIndex: Int) -> Int? {
        guard !playableFiles.isEmpty else { return nil }

        var prevIndex = playingIndex - 1
        if prevIndex < 0 { prevIndex = playableFiles.count - 1 }
        return prevIndex
    }

    /// 次の曲を再生
    /// - Parameter browserVM: ファイルブラウザViewModel
    nonisolated func playNextFile(browserVM: FileBrowserViewModel) {
        Task { @MainActor in
            let files = browserVM.playableFiles
            guard let idx = nextFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex),
                  idx < files.count else { return }

            browserVM.playingIndex = idx
            await load(url: files[idx].url)
            play()
        }
    }

    /// 前の曲を再生
    /// - Parameter browserVM: ファイルブラウザViewModel
    nonisolated func playPrevFile(browserVM: FileBrowserViewModel) {
        Task { @MainActor in
            let files = browserVM.playableFiles
            guard let idx = prevFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex),
                  idx < files.count else { return }

            browserVM.playingIndex = idx
            await load(url: files[idx].url)
            play()
        }
    }

    // MARK: - 表示更新タイマー

    private func startDisplayUpdates() {
        Log.debug("[PlayerVM] startDisplayUpdates - START")
        displayTask?.cancel()
        displayTask = Task { @MainActor in
            Log.debug("[PlayerVM] startDisplayUpdates - Task started on MainActor")
            displayFrameCount = 0
            while !Task.isCancelled && (status == .playing || fadeOutTask != nil) {
                updateDisplay()
                try? await Task.sleep(for: .seconds(1.0 / 120.0))
            }
            Log.debug("[PlayerVM] startDisplayUpdates - Task ended")
        }
        Log.debug("[PlayerVM] startDisplayUpdates - END")
    }

    private func updateDisplay() {
        guard status == .playing || fadeOutTask != nil else { return }

        // フレームカウンタをインクリメント
        displayFrameCount += 1

        // 再生時間計算（Timer から呼ばれているため メインスレッド上）
        var ms = playStartTimeMs + Int(Date().timeIntervalSince(playStartDate) * 1000)

        if abs(ms - lastSyncTimeMs) >= syncIntervalMs {
            ms = audioService.currentPlayTimeMs()
            playStartDate = Date()
            playStartTimeMs = ms
            lastSyncTimeMs = ms
            lastSyncDate = Date()
        }

        if displayFrameCount % 120 == 0 {
            Log.debug("[PlayerVM] updateDisplay - frame: \(displayFrameCount), currentTimeMs: \(ms)")
        }

        // バックグラウンドで実行（計算処理）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // チャンネル状態の取得（キーボード・レベルメーター: 毎フレーム 120fps）
            let fmChannels = channelService.getChannels(currentTimeMs: ms)

            // スペアナ計算は 60fps（2フレームごと）
            var newBars = self.spectrumBars
            let shouldUpdateSpectrum = (self.displayFrameCount % 2) == 0
            if shouldUpdateSpectrum {
                newBars = spectrumService.computeSpectrum(for: fmChannels, currentBars: spectrumBars)
            }

            // メインスレッドで UI 更新
            DispatchQueue.main.async {
                // チャンネル状態・レベルメーター（毎フレーム 120fps）
                self.channels = fmChannels

                // スペアナ・currentTimeMs（2フレームごと 60fps）
                if shouldUpdateSpectrum {
                    self.currentTimeMs = ms
                    self.spectrumBars = newBars

                    if self.totalTimeMs > 0 && self.currentTimeMs >= self.totalTimeMs {
                        self.handleTrackEnd()
                    }
                }
            }
        }
    }

    // MARK: - 曲終了ハンドリング

    private func handleTrackEnd() {
        guard status == .playing else { return }

        status = .stopped

        Log.debug("[TrackEnd] autoMode=\(autoMode)")
        startFadeOut()
    }

    private func startFadeOut() {
        Log.debug("[FadeOut] Starting fadeout (autoMode=\(autoMode))")
        fadeOutVolume = 1.0
        let fadeOutSteps = 60
        let decrement = 1.0 / Float(fadeOutSteps)

        fadeOutTask = Task {
            for step in 0..<fadeOutSteps {
                guard !Task.isCancelled else {
                    Log.debug("[FadeOut] Cancelled at step \(step)")
                    break
                }

                try? await Task.sleep(nanoseconds: 50_000_000)

                await MainActor.run {
                    self.fadeOutVolume = max(0.0, self.fadeOutVolume - decrement)
                    self.audioService.setVolume(self.fadeOutVolume)
                }
            }

            await MainActor.run {
                Log.debug("[FadeOut] Complete (autoMode=\(self.autoMode))")
                self.fadeOutVolume = 1.0
                self.audioService.setVolume(1.0)
                self.displayTask?.cancel()
                self.displayTask = nil
                self.fadeOutTask = nil
                if !Task.isCancelled {
                    switch self.autoMode {
                    case .normal:
                        self.stop()
                    case .auto:
                        self.playNextTrack()
                    case .random:
                        self.playRandomTrack()
                    }
                }
            }
        }
    }

    private func playNextTrack() {
        Log.debug("[NextTrack] AUTO mode - playing next track")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let browserVM = self.browserVM else {
                self?.stop()
                return
            }

            let files = browserVM.playableFiles
            guard !files.isEmpty else {
                self.stop()
                return
            }

            if let nextIdx = self.nextFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex) {
                browserVM.playingIndex = nextIdx
                Task {
                    await self.load(url: files[nextIdx].url)
                    self.play()
                }
            } else {
                self.stop()
            }
        }
    }

    private func playRandomTrack() {
        Log.debug("[RandomTrack] SHUFFLE mode - playing random track")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let browserVM = self.browserVM else {
                self?.stop()
                return
            }

            let files = browserVM.playableFiles
            guard !files.isEmpty else {
                self.stop()
                return
            }

            let randomIdx = Int.random(in: 0..<files.count)
            browserVM.playingIndex = randomIdx
            Task {
                await self.load(url: files[randomIdx].url)
                self.play()
            }
        }
    }

    private func clearVisualState() {
        channels = Array(repeating: ChannelDisplayState(), count: 16)
        spectrumBars = Array(repeating: SpectrumBarState(), count: 52)
    }
}
