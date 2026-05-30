import Foundation

/// トラック遷移（曲終了・フェードアウト・自動再生）を管理する
@MainActor
protocol TrackTransitionManagerDelegate: AnyObject {
    func loadAndPlay(url: URL) async
    func stopPlayback()
    func setAudioVolume(_ volume: Float)
}

@MainActor
final class TrackTransitionManager {
    weak var delegate: TrackTransitionManagerDelegate?
    weak var browserVM: FileBrowserViewModel?

    var autoMode: AutoMode = .normal

    private var fadeOutTask: Task<Void, Never>?
    private var fadeOutVolume: Float = 1.0
    private(set) var isFadingOut: Bool = false

    // MARK: - 曲終了 / フェードアウト

    func handleTrackEnd() {
        guard !isFadingOut else { return }
        isFadingOut = true
        startFadeOut()
    }

    func cancelFadeOut() {
        fadeOutTask?.cancel()
        fadeOutTask = nil
        isFadingOut = false
        fadeOutVolume = 1.0
    }

    private func startFadeOut() {
        fadeOutVolume = 1.0
        let fadeOutSteps = 60
        let decrement = 1.0 / Float(fadeOutSteps)

        fadeOutTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for step in 0..<fadeOutSteps {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
                fadeOutVolume = max(0.0, fadeOutVolume - decrement)
                delegate?.setAudioVolume(fadeOutVolume)
            }

            fadeOutVolume = 1.0
            delegate?.setAudioVolume(1.0)
            fadeOutTask = nil
            isFadingOut = false

            if !Task.isCancelled {
                switch autoMode {
                case .normal:
                    delegate?.stopPlayback()
                case .auto:
                    playNextTrack()
                case .random:
                    playRandomTrack()
                }
            }
        }
    }

    // MARK: - インデックス計算

    func nextFileIndex(playableFiles: [FileItem], playingIndex: Int) -> Int? {
        guard !playableFiles.isEmpty else { return nil }
        var nextIndex = playingIndex + 1
        if autoMode == .random {
            nextIndex = Int.random(in: 0..<playableFiles.count)
        }
        if nextIndex >= playableFiles.count { nextIndex = 0 }
        return nextIndex
    }

    func prevFileIndex(playableFiles: [FileItem], playingIndex: Int) -> Int? {
        guard !playableFiles.isEmpty else { return nil }
        var prevIndex = playingIndex - 1
        if prevIndex < 0 { prevIndex = playableFiles.count - 1 }
        return prevIndex
    }

    // MARK: - トラック遷移

    func playNextFile(browserVM: FileBrowserViewModel) {
        let files = browserVM.playableFiles
        guard let idx = nextFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex),
              idx < files.count else { return }
        browserVM.playingIndex = idx
        Task {
            await delegate?.loadAndPlay(url: files[idx].url)
        }
    }

    func playPrevFile(browserVM: FileBrowserViewModel) {
        let files = browserVM.playableFiles
        guard let idx = prevFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex),
              idx < files.count else { return }
        browserVM.playingIndex = idx
        Task {
            await delegate?.loadAndPlay(url: files[idx].url)
        }
    }

    private func playNextTrack() {
        guard let browserVM else {
            delegate?.stopPlayback()
            return
        }

        let files = browserVM.playableFiles
        guard !files.isEmpty else {
            delegate?.stopPlayback()
            return
        }

        if let nextIdx = nextFileIndex(playableFiles: files, playingIndex: browserVM.playingIndex) {
            browserVM.playingIndex = nextIdx
            Task {
                await delegate?.loadAndPlay(url: files[nextIdx].url)
            }
        } else {
            delegate?.stopPlayback()
        }
    }

    private func playRandomTrack() {
        guard let browserVM else {
            delegate?.stopPlayback()
            return
        }

        let files = browserVM.playableFiles
        guard !files.isEmpty else {
            delegate?.stopPlayback()
            return
        }

        let randomIdx = Int.random(in: 0..<files.count)
        browserVM.playingIndex = randomIdx
        Task {
            await delegate?.loadAndPlay(url: files[randomIdx].url)
        }
    }
}
