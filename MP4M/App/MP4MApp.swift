import SwiftUI
import CoreText
import Foundation

// MARK: - 簡易ロガー（環境変数 MP4M_LOG で制御）

enum Log {
    static let enabled = ProcessInfo.processInfo.environment["MP4M_LOG"] != nil
    static func debug(_ message: String) {
        guard enabled else { return }
        print(message)
    }
}

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

    /// ウィンドウを閉じたらアプリを終了する（macOS 既定の「閉じても常駐」を無効化）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// コマンドライン引数で渡されたパス（FileBrowserViewModel が init で参照する）
    static var pendingPath: String?

    /// ContentView が表示され、ファイル開封通知を受け取れる状態か
    ///
    /// Finder のダブルクリックでは `application:openFile:` が起動シーケンスのどこで
    /// 呼ばれるか一定しないため、UI 準備前は pendingPath に積み、準備後は通知で渡す。
    static var isUIReady = false

    init() {
        setbuf(stdout, nil)
        Self.pendingPath = Self.parseCLIArg()
        registerFonts()
        Self.handleSingleInstance()
    }

    var body: some Scene {
        // Window（単一ウィンドウ）を使う。WindowGroup ではドキュメントを開く要求で
        // ウィンドウが増え、ContentView とオーディオエンジンが二重に生成されてしまう
        Window("MP4M", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    // MARK: - AppKit Delegate（ファイル開封要求の処理）

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationWillFinishLaunching(_ notification: Notification) {
            Log.debug("[AppDelegate] applicationWillFinishLaunching pendingPath=\(MP4MApp.pendingPath ?? "nil")")
            // 転送するだけの二重起動インスタンスは UI を出さない
            if MP4MApp.isSecondaryInstance {
                NSApp.setActivationPolicy(.prohibited)
            }
        }

        /// ウィンドウを閉じたらアプリを終了する（macOS 既定の「閉じても常駐」を無効化）
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        func applicationWillTerminate(_ notification: Notification) {
            // View のライフサイクルではなくアプリ終了時にオーディオを解放する
            MainActor.assumeIsolated {
                AppServices.shared.cleanup()
            }
        }

        func application(_ sender: NSApplication, openFile path: String) -> Bool {
            Log.debug("[AppDelegate] application:openFile: \(path)")
            MP4MApp.requestOpen(path: path)
            return true
        }

        func application(_ application: NSApplication, open urls: [URL]) {
            Log.debug("[AppDelegate] application:open urls: \(urls.map(\.path))")
            for url in urls where url.isFileURL {
                MP4MApp.requestOpen(path: url.path)
            }
        }
    }

    /// ファイル開封要求を UI へ渡す
    ///
    /// UI 準備前は pendingPath に積み、ContentView の onAppear で拾わせる。
    static func requestOpen(path: String) {
        if isSecondaryInstance {
            forwardToFirstInstanceAndExit(path: path)
        }
        if isUIReady {
            NotificationCenter.default.post(name: .mp4mOpenFile, object: path)
        } else if pendingPath == nil {
            pendingPath = path
        }
    }

    // MARK: - フォント登録
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

    /// 先行インスタンスが存在する状態で起動したか（ファイル転送後に終了する）
    static var isSecondaryInstance = false

    /// 開封要求を先行インスタンスへ転送して自分は終了する
    static func forwardToFirstInstanceAndExit(path: String) -> Never {
        Log.debug("[Singleton] Sending MP4MOpenFile notification to first instance: \(path)")
        let center = CFNotificationCenterGetDistributedCenter()
        let name = CFNotificationName("MP4MOpenFile" as CFString)
        let object = Unmanaged.passUnretained(path as CFString).toOpaque()
        CFNotificationCenterPostNotification(center, name, object, nil, true)
        // 配送を取りこぼさないよう少し待ってから終了する
        Thread.sleep(forTimeInterval: 0.2)
        exit(0)
    }

    static func handleSingleInstance() {
        let cliPath = Self.pendingPath
        Log.debug("[Singleton] pendingPath: \(cliPath ?? "nil")")

        let lockPath = "/tmp/com.ktam.MP4M.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        let isFirst = (fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
        print("[MP4MApp] handleSingleInstance - isFirst: \(isFirst)")

        if isFirst {
            Log.debug("[Singleton] lock acquired (first instance)")
        } else {
            Log.debug("[Singleton] lock failed (second instance)")
        }

        if isFirst {
            Self.lockFD = fd

            Log.debug("[Singleton] pendingPath kept as: \(cliPath ?? "nil")")
            setupFileOpenObserver()
        } else {
            if fd >= 0 { close(fd) }
            if let path = cliPath {
                Self.forwardToFirstInstanceAndExit(path: path)
            }
            // Finder のダブルクリックではパスが application:openFile: で後から届くため、
            // すぐに exit せず短時間だけ待つ（届けば転送して終了、届かなければ終了）
            Log.debug("[Singleton] Second instance without CLI arg, waiting for openFile")
            Self.isSecondaryInstance = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Log.debug("[Singleton] No openFile arrived, exiting")
                exit(0)
            }
        }
    }

    /// コマンドライン引数からパスを取得
    private static func parseCLIArg() -> String? {
        let args = CommandLine.arguments
        Log.debug("[CLI] CommandLine.arguments: \(args)")
        guard args.count > 1 else { return nil }

        for i in 1..<args.count {
            let raw = args[i]
            let path: String
            if raw.hasPrefix("--file=") {
                path = String(raw.dropFirst(7))
            } else if raw.hasPrefix("--dir=") {
                path = String(raw.dropFirst(6))
            } else {
                path = raw
            }

            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
                continue
            }

            Log.debug("[CLI] Valid path: \(expanded) (isDir=\(isDir.boolValue))")
            return expanded
        }

        return nil
    }

    private static var fileOpenObserverInstalled = false

    static func setupFileOpenObserver() {
        // ContentView の onAppear からも呼ばれるため、二重登録を防ぐ
        guard !fileOpenObserverInstalled else { return }
        fileOpenObserverInstalled = true

        DistributedNotificationCenter.default().addObserver(
            forName: .init("MP4MOpenFile"),
            object: nil,
            queue: .main
        ) { notification in
            guard let path = notification.object as? String else {
                Log.debug("[IPC] Received MP4MOpenFile but object is not String: \(String(describing: notification.object))")
                return
            }
            Log.debug("[IPC] Received MP4MOpenFile from second instance: \(path)")
            NotificationCenter.default.post(name: .mp4mOpenFile, object: path)
        }
    }
}
