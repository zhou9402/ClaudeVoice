// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeVoice15",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/ivan-digital/qwen3-asr-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeVoice15",
            dependencies: [
                .product(name: "Qwen3ASR", package: "qwen3-asr-swift"),
            ],
            path: "Sources/ClaudeVoice15",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
