import SwiftUI

struct ContentView: View {
    @State private var playerVM: PlayerViewModel?
    @State private var browserVM = FileBrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            TrackInfoView(viewModel: playerVM)
                .frame(height: 48)
            Divider().background(Color.mmdspBorder)
            HStack(spacing: 0) {
                SpectrumAnalyzerView(viewModel: playerVM)
                    .frame(width: 480)
                Divider().background(Color.mmdspBorder)
                LevelMeterView(viewModel: playerVM)
            }
            .frame(height: 180)
            Divider().background(Color.mmdspBorder)
            KeyboardView(viewModel: playerVM)
                .frame(height: 148)
            Divider().background(Color.mmdspBorder)
            if let playerVM {
                FileSelectorView(browserVM: browserVM, playerVM: playerVM)
                    .frame(minHeight: 180)
            }
            Divider().background(Color.mmdspBorder)
            ControlPanelView(viewModel: playerVM, browserVM: browserVM)
                .frame(height: 44)
        }
        .background(Color.mmdspBackground)
        .foregroundColor(Color.mmdspText)
        .onAppear {
            playerVM = PlayerViewModel(audioService: MXDRVAudioEngine())
        }
        .onDisappear {
            playerVM?.cleanup()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
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
