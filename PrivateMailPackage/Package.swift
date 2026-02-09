// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PrivateMailFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "PrivateMailFeature",
            targets: ["PrivateMailFeature"]
        ),
    ],
    dependencies: [
        // llama.cpp via prebuilt XCFramework — proper semantic versioning, no unsafeFlags.
        // Tracks upstream llama.cpp builds automatically (version scheme: 2.{build}.0).
        .package(url: "https://github.com/mattt/llama.swift", from: "2.7972.0"),
    ],
    targets: [
        .target(
            name: "PrivateMailFeature",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            resources: [.copy("Resources/tracking_domains.json")]
        ),
        .testTarget(
            name: "PrivateMailFeatureTests",
            dependencies: [
                "PrivateMailFeature"
            ]
        ),
    ]
)
