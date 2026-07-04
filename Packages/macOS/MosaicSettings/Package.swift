// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSettings",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSettings",
            targets: ["MosaicSettings"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicSettings",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ]
        ),
        .testTarget(
            name: "MosaicSettingsTests",
            dependencies: ["MosaicSettings"]
        ),
    ]
)
