import SwiftUI
import CoreText

@main
struct MP4MApp: App {
    init() {
        // カスタムドットフォントを登録 (KH-Dot-Kodenmachou-16)
        if let url = Bundle.main.url(forResource: "KH-Dot-Kodenmachou-16-Ki", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
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
