// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Trigger",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Trigger",
            path: "Sources"
        ),
    ]
)
