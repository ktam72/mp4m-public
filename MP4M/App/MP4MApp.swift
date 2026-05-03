import SwiftUI
import CoreText

@main
struct MP4MApp: App {
    init() {
        // Monaspace Neon フォントを登録
        let fontNames = ["MonaspaceNeon-Regular", "MonaspaceNeon-Bold"]
        for fontName in fontNames {
            if let url = Bundle.main.url(forResource: fontName, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        Window("MP4M", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
