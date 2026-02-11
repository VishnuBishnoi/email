// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VaultMailFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "VaultMailFeature",
            targets: ["VaultMailFeature"]
        ),
    ],
    dependencies: [
        // llama.cpp via prebuilt XCFramework — proper semantic versioning, no unsafeFlags.
        // Tracks upstream llama.cpp builds automatically (version scheme: 2.{build}.0).
        .package(url: "https://github.com/mattt/llama.swift", from: "2.7972.0"),
    ],
    targets: [
        .target(
            name: "VaultMailFeature",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            resources: [.copy("Resources/tracking_domains.json")]
        ),
        .testTarget(
            name: "VaultMailFeatureTests",
            dependencies: [
                "VaultMailFeature"
            ]
        ),
    ]
)
