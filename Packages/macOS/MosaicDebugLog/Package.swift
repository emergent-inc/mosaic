// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MosaicDebugLog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MosaicDebugLog",
            targets: ["MosaicDebugLog"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicDebugLog",
            path: "Sources/MosaicDebugLog"
        ),
        .testTarget(
            name: "MosaicDebugLogTests",
            dependencies: ["MosaicDebugLog"],
            path: "Tests/MosaicDebugLogTests"
        ),
    ]
)
