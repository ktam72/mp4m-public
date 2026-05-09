import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var playerVM: PlayerViewModel?
    @State private var browserVM = FileBrowserViewModel()
    @State private var showAbout = false
    @State private var ipcFileURL: URL?
    @State private var hasActivated = false

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
                playerVM = PlayerViewModel(audioService: MXDRVAudioEngine())
                playerVM?.browserVM = browserVM

                if let fileURL = browserVM.launchFileURL {
                    Task {
                        await playerVM?.load(url: fileURL)
                        await playerVM?.playAsync()
                    }
                }
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !hasActivated {
                    hasActivated = true
                    DispatchQueue.main.async {
                        activateWindow()
                    }
                }
            }
            .background(WindowActivator())
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

    private func activateWindow() {
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// 初回起動時にウィンドウを確実に前面に出すための NSViewRepresentable
private struct WindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ActivatingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class ActivatingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                DispatchQueue.main.async {
                    if let win = NSApplication.shared.windows.first {
                        win.makeKeyAndOrderFront(nil)
                    }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
