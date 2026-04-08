// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeVoice9",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeVoice9",
            path: "Sources/ClaudeVoice9",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
