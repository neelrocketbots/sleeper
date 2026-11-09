import AppKit

/// The entry points the executable calls.
@MainActor public enum SleeperLauncher {
    public static func cutAssets(raw: String, out: String) throws {
        try AssetCutter.run(raw: URL(fileURLWithPath: raw), out: URL(fileURLWithPath: out))
    }

    public static func run(arguments: [String]) {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if let i = arguments.firstIndex(of: "--snapshots"), i + 1 < arguments.count {
            delegate.snapshotDir = URL(fileURLWithPath: arguments[i + 1])
        }
        delegate.selfTest = arguments.contains("--selftest")
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

