// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapCue",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SnapCueCore"),
        .executableTarget(name: "SnapCue", dependencies: ["SnapCueCore"]),
        .testTarget(name: "SnapCueCoreTests", dependencies: ["SnapCueCore"])
    ]
)
