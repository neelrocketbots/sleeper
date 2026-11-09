import AppKit
import SleeperApp

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--art-preview"), i + 1 < args.count {
    MainActor.assumeIsolated {
        do { try SleeperLauncher.writeArtPreview(to: args[i + 1]) } catch { print("art preview failed: \(error)") }
    }
    exit(0)
}
if let i = args.firstIndex(of: "--vector-sample"), i + 1 < args.count {
    MainActor.assumeIsolated {
        do { try SleeperLauncher.writeVectorSample(to: args[i + 1]) } catch { print("vector sample failed: \(error)") }
    }
    exit(0)
}
MainActor.assumeIsolated { SleeperLauncher.run(arguments: args) }
