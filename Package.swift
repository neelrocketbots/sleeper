// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sleeper",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Sleeper", targets: ["Sleeper"])],
    dependencies: [
        .package(url: "https://github.com/neelrocketbots/notchkit.git", branch: "main"),
    ],
    targets: [
        // Game rules, map, AI and meetings. No AppKit, SpriteKit or SwiftUI, so a network layer can drive it later.
        .target(name: "SleeperCore"),
        .target(name: "SleeperApp",
                dependencies: ["SleeperCore", .product(name: "NotchKit", package: "notchkit")],
                resources: [.copy("Assets")]),
        .executableTarget(name: "Sleeper", dependencies: ["SleeperApp"]),
        .testTarget(name: "SleeperCoreTests", dependencies: ["SleeperCore"]),
    ]
)
