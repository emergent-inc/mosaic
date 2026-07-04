// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSettingsUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSettingsUI",
            targets: ["MosaicSettingsUI"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicSettings"),
    ],
    targets: [
        .target(
            name: "MosaicSettingsUI",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicSettings", package: "MosaicSettings"),
            ]
        ),
        .testTarget(
            name: "MosaicSettingsUITests",
            dependencies: ["MosaicSettingsUI"]
        ),
    ]
)
