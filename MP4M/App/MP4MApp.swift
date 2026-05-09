import SwiftUI
import CoreText

extension Notification.Name {
    static let mp4mOpenFile = Notification.Name("MP4MOpenFileRequest")
}

@main
struct MP4MApp: App {
    static var pendingPath: String?

    init() {
        registerFonts()
        handleSingleInstance()
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

    private func handleSingleInstance() {
        let cliPath = Self.parseCLIArg()

        let lockPath = "/tmp/com.ktam.MP4M.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        let isFirst = (fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)

        if isFirst {
            Self.lockFD = fd
            Self.pendingPath = cliPath
        } else {
            if fd >= 0 { close(fd) }
            if let path = cliPath {
                let center = CFNotificationCenterGetDistributedCenter()
                let name = CFNotificationName("MP4MOpenFile" as CFString)
                let object = Unmanaged.passUnretained(path as CFString).toOpaque()
                CFNotificationCenterPostNotification(center, name, object, nil, true)
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
