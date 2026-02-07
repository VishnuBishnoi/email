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
    targets: [
        .target(
            name: "PrivateMailFeature"
        ),
        .testTarget(
            name: "PrivateMailFeatureTests",
            dependencies: [
                "PrivateMailFeature"
            ]
        ),
    ]
)
