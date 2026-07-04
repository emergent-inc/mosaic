// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicAuthCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAuthCore",
            targets: ["MosaicAuthCore"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicAuthCore"
        ),
        .testTarget(
            name: "MosaicAuthCoreTests",
            dependencies: ["MosaicAuthCore"]
        ),
    ]
)
