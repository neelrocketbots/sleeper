import AppKit

/// The entry points the executable calls.
@MainActor public enum SleeperLauncher {
    public static func writeArtPreview(to path: String) throws {
        try ArtPreview.write(to: URL(fileURLWithPath: path))
    }

    public static func writeVectorSample(to path: String) throws {
        try VectorSample.write(to: URL(fileURLWithPath: path))
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

