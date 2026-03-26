// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "generate-cache",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/mattt/llama.swift.git", from: "2.8530.0"),
    ],
    targets: [
        .executableTarget(
            name: "generate-cache",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            path: "Sources"
        ),
    ]
)
