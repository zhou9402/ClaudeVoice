// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeVoice17",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/ivan-digital/qwen3-asr-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeVoice17",
            dependencies: [
                .product(name: "Qwen3ASR", package: "qwen3-asr-swift"),
            ],
            path: "Sources/ClaudeVoice17",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
