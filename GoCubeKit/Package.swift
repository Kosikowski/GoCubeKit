// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoCubeKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GoCubeKit",
            targets: ["GoCubeKit"]
        ),
    ],
    targets: [
        .target(
            name: "GoCubeKit",
            dependencies: [],
            path: "Sources/GoCubeKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GoCubeKitTests",
            dependencies: ["GoCubeKit"],
            path: "Tests/GoCubeKitTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
