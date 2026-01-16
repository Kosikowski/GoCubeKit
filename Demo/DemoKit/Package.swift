// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DemoKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DemoKit", targets: ["DemoKit"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "DemoKit",
            dependencies: ["GoCubeKit"]
        ),
    ]
)
