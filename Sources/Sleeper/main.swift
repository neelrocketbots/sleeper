import AppKit
import SleeperApp

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--cut-assets"), i + 2 < args.count {
    MainActor.assumeIsolated {
        do { try SleeperLauncher.cutAssets(raw: args[i + 1], out: args[i + 2]) } catch { print("cutting failed: \(error)") }
    }
    exit(0)
}
MainActor.assumeIsolated { SleeperLauncher.run(arguments: args) }
