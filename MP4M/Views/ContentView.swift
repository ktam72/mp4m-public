import SwiftUI

struct ContentView: View {
    @State private var playerVM: PlayerViewModel?
    @State private var browserVM = FileBrowserViewModel()
    @State private var showAbout = false
    @State private var ipcFileURL: URL?
    @State private var isAppActivated = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TrackInfoView(viewModel: playerVM, showAbout: $showAbout)
                    .frame(height: 56)
                Divider().background(Color.mp4mBorder)
                HStack(spacing: 0) {
                    SpectrumAnalyzerView(viewModel: playerVM)
                        .frame(width: 480)
                    Divider().background(Color.mp4mBorder)
                    LevelMeterView(viewModel: playerVM)
                }
                .frame(height: 180)
                Divider().background(Color.mp4mBorder)
                KeyboardView(viewModel: playerVM)
                    .frame(height: 300)
                Divider().background(Color.mp4mBorder)
                if let playerVM {
                    FileSelectorView(browserVM: browserVM, playerVM: playerVM)
                }
                Divider().background(Color.mp4mBorder)
                ControlPanelView(viewModel: playerVM, browserVM: browserVM)
                    .frame(height: 44)
            }
            .disabled(showAbout)
            .background(Color.mp4mBackground)
            .foregroundColor(Color.mp4mText)
            .onAppear {
                print("[ContentView] onAppear - START")
                print("[ContentView] pendingPath: \(MP4MApp.pendingPath ?? "nil")")
                print("[ContentView] launchFileURL: \(browserVM.launchFileURL?.path ?? "nil")")

                playerVM = PlayerViewModel(audioService: MXDRVAudioEngine())
                playerVM?.browserVM = browserVM
                MP4MApp.setupFileOpenObserver()
                print("[ContentView] PlayerViewModel initialized")

                // ウィンドウを前面に表示
                activateWindow()

                // アプリがアクティベートされた後に再生を開始
                if let fileURL = browserVM.launchFileURL {
                    print("[ContentView] Starting playback task for: \(fileURL.path)")
                    Task { @MainActor in
                        // アプリのアクティベーション完了を待機
                        await waitForAppActivation()
                        print("[ContentView] waitForAppActivation done")

                        // ウィンドウが前面に表示されたことを確認するために少し待機
                        try? await Task.sleep(for: .milliseconds(100))

                        print("[ContentView] Calling load(url:)")
                        await playerVM?.load(url: fileURL)
                        print("[ContentView] Calling playAsync()")
                        await playerVM?.playAsync()
                        print("[ContentView] Playback task complete")
                    }
                } else {
                    print("[ContentView] No launchFileURL, skipping auto-play")
                }
                print("[ContentView] onAppear - END")
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDidActivate)) { _ in
                print("[ContentView] Received appDidActivate notification")
                isAppActivated = true
            }
            .onDisappear {
                playerVM?.cleanup()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
            .onReceive(NotificationCenter.default.publisher(for: .mp4mOpenFile)) { notification in
                guard let path = notification.object as? String else { return }
                handleIncomingFile(path: path)
            }
            .alert(item: Binding(
                get: { playerVM?.currentError },
                set: { playerVM?.currentError = $0 }
            )) { error in
                Alert(
                    title: Text("エラー"),
                    message: Text(error.errorDescription ?? "不明なエラーが発生しました。"),
                    dismissButton: .default(Text("OK")) {
                        playerVM?.currentError = nil
                    }
                )
            }

            // About ダイアログオーバーレイ
            if showAbout {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { showAbout = false }
                AboutView(isPresented: $showAbout)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, let playerVM else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "mdx" else { return }
            Task { @MainActor in
                await playerVM.load(url: url)
                playerVM.play()
            }
        }
        return true
    }

    /// 他インスタンスからのファイル開封要求を処理
    private func handleIncomingFile(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }

        let url = URL(fileURLWithPath: path)

        if isDir.boolValue {
            browserVM.openDirectory(url)
            return
        }

        let parentDir = url.deletingLastPathComponent()
        browserVM.openDirectory(parentDir)
        if let index = browserVM.playableFiles.firstIndex(where: { $0.url.path == url.path }) {
            browserVM.playingIndex = index
        }

        NSApp.activate(ignoringOtherApps: true)

        guard let playerVM else { return }
        Task {
            await playerVM.load(url: url)
            await playerVM.playAsync()
        }
    }

    /// アプリのアクティベーション完了を待機
    private func waitForAppActivation() async {
        print("[ContentView] waitForAppActivation - START, isAppActivated: \(isAppActivated)")
        // すでにアクティベート済みの場合は即座にリターン
        guard !isAppActivated else {
            print("[ContentView] waitForAppActivation - Already activated")
            return
        }

        // タイムアウト付きで待機（最大2秒）
        let timeout: TimeInterval = 2.0
        let startTime = Date()

        while !isAppActivated && Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(for: .milliseconds(50))
        }
        print("[ContentView] waitForAppActivation - END, isAppActivated: \(isAppActivated)")
    }

    /// ウィンドウを前面に表示
    private func activateWindow() {
        // ウィンドウが見つかるまで一定間隔でリトライ
        Task { @MainActor in
            for attempt in 1...10 {
                if let window = NSApp.windows.first {
                    print("[ContentView] Activating window (attempt \(attempt)): \(window.title)")
                    window.level = .floating
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    // 0.5秒後に通常のレベルに戻す
                    try? await Task.sleep(for: .milliseconds(500))
                    window.level = .normal

                    self.isAppActivated = true
                    return
                }
                print("[ContentView] No window found, attempt \(attempt)/10")
                try? await Task.sleep(for: .milliseconds(100))
            }
            print("[ContentView] Failed to find window after 10 attempts")
        }
    }
}
