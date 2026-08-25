import Foundation

/// アプリ全体で共有する ViewModel を保持する
///
/// オーディオエンジン（MXDRVG）はプロセスに 1 つしかなく、
/// `PlayerViewModel` の生成で開始・`cleanup()` で破棄される。
/// View のライフサイクルに紐付けると、ウィンドウの再構成で
/// 二重生成（再生速度が倍になる）やエンジン破棄後の再生（クラッシュ）を招くため、
/// アプリ側で一度だけ生成して共有する。
@MainActor
final class AppServices {
    static let shared = AppServices()

    let browserVM = FileBrowserViewModel()
    lazy var playerVM: PlayerViewModel = {
        let viewModel = PlayerViewModel(audioService: MXDRVAudioEngine())
        viewModel.browserVM = browserVM
        return viewModel
    }()

    /// アプリ終了時のクリーンアップ（View の onDisappear では呼ばない）
    func cleanup() {
        playerVM.cleanup()
    }

    private init() {}
}
