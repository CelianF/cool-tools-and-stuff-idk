// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoolTools",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CoolTools",
            path: "Sources/CoolTools",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
