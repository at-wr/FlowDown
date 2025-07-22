// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChatClientKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS("13.3"),
    ],
    products: [
        .library(name: "ChatClientKit", targets: ["ChatClientKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
        .package(url: "https://github.com/loopwork-ai/eventsource", from: "1.1.1"),
    ],
    targets: [
        .target(
            name: "ChatClientKit",
            dependencies: [
                "ServerEvent",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXVLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "EventSource", package: "EventSource"),
            ]
        ),
        .target(name: "ServerEvent"),
    ]
)
