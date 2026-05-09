import SwiftUI
import CoreText

extension Notification.Name {
    static let mp4mOpenFile = Notification.Name("MP4MOpenFileRequest")
    static let appDidActivate = Notification.Name("MP4MAppDidActivate")
}

/// CLI起動時のウィンドウアクティベーションと再生開始を制御するデリゲート
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasActivated = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationWillFinishLaunching - START")
        // 非常に重要: CLI起動時にアクティベーションポリシーを事前に設定
        NSApp.setActivationPolicy(.regular)
        print("[AppDelegate] applicationWillFinishLaunching - END")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching - START")
        print("[AppDelegate] windows count: \(NSApp.windows.count)")

        // アプリを前面に表示
        NSApp.activate(ignoringOtherApps: true)

        // アクティベーション完了をContentViewに通知
        NotificationCenter.default.post(name: .appDidActivate, object: nil)
        print("[AppDelegate] applicationDidFinishLaunching - END")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        print("[AppDelegate] applicationDidBecomeActive - START")
        guard !hasActivated else { return }
        hasActivated = true

        // ウィンドウを前面に表示
        if let window = NSApp.windows.first {
            print("[AppDelegate] Activating window: \(window.title)")
            window.level = .floating
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                window.level = .normal
            }
        }
        print("[AppDelegate] applicationDidBecomeActive - END")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("[AppDelegate] applicationShouldHandleReopen - hasVisibleWindows: \(flag)")
        if !flag {
            if let window = NSApp.windows.first {
                window.orderFrontRegardless()
            }
        }
        return true
    }
}

@main
struct MP4MApp: App {
    static var pendingPath: String?

    init() {
        registerFonts()
        Self.handleSingleInstance()
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

    private func registerFonts() {
        let fontNames = ["MonaspaceNeon-Regular", "MonaspaceNeon-Bold"]
        for fontName in fontNames {
            if let url = Bundle.main.url(forResource: fontName, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // MARK: - シングルインスタンス制御

    private static var lockFD: Int32 = -1

    static func handleSingleInstance() {
        let cliPath = Self.parseCLIArg()
        print("[MP4MApp] handleSingleInstance - cliPath: \(cliPath ?? "nil")")

        let lockPath = "/tmp/com.ktam.MP4M.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        let isFirst = (fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
        print("[MP4MApp] handleSingleInstance - isFirst: \(isFirst)")

        if isFirst {
            Self.lockFD = fd
            Self.pendingPath = cliPath
            print("[MP4MApp] handleSingleInstance - First instance, pendingPath set")
        } else {
            if fd >= 0 { close(fd) }
            if let path = cliPath {
                let center = CFNotificationCenterGetDistributedCenter()
                let name = CFNotificationName("MP4MOpenFile" as CFString)
                let object = Unmanaged.passUnretained(path as CFString).toOpaque()
                CFNotificationCenterPostNotification(center, name, object, nil, true)
                print("[MP4MApp] handleSingleInstance - Second instance, sent notification")
            }
            exit(0)
        }
    }

    private static func parseCLIArg() -> String? {
        let args = CommandLine.arguments
        guard args.count > 1 else { return nil }
        let path = (args[1] as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        return path
    }

    static func setupFileOpenObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("MP4MOpenFile"),
            object: nil,
            queue: .main
        ) { notification in
            guard let path = notification.object as? String else { return }
            NotificationCenter.default.post(name: .mp4mOpenFile, object: path)
        }
    }
}
