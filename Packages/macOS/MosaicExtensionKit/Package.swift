// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicExtensionKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicExtensionKit",
            targets: ["MosaicExtensionKit"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicExtensionKit"
        ),
        .testTarget(
            name: "MosaicExtensionKitTests",
            dependencies: ["MosaicExtensionKit"]
        ),
    ]
)
