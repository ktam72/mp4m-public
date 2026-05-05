import SwiftUI

struct ContentView: View {
    @State private var playerVM: PlayerViewModel?
    @State private var browserVM = FileBrowserViewModel()
    @State private var showAbout = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TrackInfoView(viewModel: playerVM, showAbout: $showAbout)
                .frame(minHeight: 48)
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
                .frame(height: 600)
            Divider().background(Color.mp4mBorder)
            if let playerVM {
                FileSelectorView(browserVM: browserVM, playerVM: playerVM)
                    .frame(minHeight: 288)
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
            }
            .onDisappear {
                playerVM?.cleanup()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
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
}
