// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoCubeKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
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
            path: "Sources/GoCubeKit"
        ),
        .testTarget(
            name: "GoCubeKitTests",
            dependencies: ["GoCubeKit"],
            path: "Tests/GoCubeKitTests"
        ),
    ]
)
