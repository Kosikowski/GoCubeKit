// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoCubeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("FullTypedThrows")
            ]
        ),
        .testTarget(
            name: "GoCubeKitTests",
            dependencies: ["GoCubeKit"],
            path: "Tests/GoCubeKitTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("FullTypedThrows")
            ]
        ),
    ]
)
