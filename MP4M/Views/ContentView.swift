import SwiftUI

struct ContentView: View {
    @State private var playerVM: PlayerViewModel?
    @State private var browserVM = FileBrowserViewModel()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                TrackInfoView(viewModel: playerVM)
                    .frame(minHeight: 48)
                Divider().background(Color.mp4mBorder)
                HStack(spacing: 0) {
                    SpectrumAnalyzerView(viewModel: playerVM)
                        .frame(width: geometry.size.width)
                    #if os(macOS)
                    Divider().background(Color.mp4mBorder)
                    LevelMeterView(viewModel: playerVM)
                    #endif
                }
                .frame(height: 180)
                Divider().background(Color.mp4mBorder)
                KeyboardView(viewModel: playerVM)
                    .frame(height: 300)
                Divider().background(Color.mp4mBorder)
                if let playerVM {
                    FileSelectorView(browserVM: browserVM, playerVM: playerVM)
                        .frame(minHeight: 288)
                }
                Divider().background(Color.mp4mBorder)
                ControlPanelView(viewModel: playerVM, browserVM: browserVM)
                    .frame(height: 44)
            }
            .background(Color.mp4mBackground)
            .foregroundColor(Color.mp4mText)
        }
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
