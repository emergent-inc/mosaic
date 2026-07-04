// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSwiftRenderUI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSwiftRenderUI",
            targets: ["MosaicSwiftRenderUI"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicSwiftRender"),
        .package(path: "../MosaicSettings"),
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicSwiftRenderUI",
            dependencies: [
                .product(name: "MosaicSwiftRender", package: "MosaicSwiftRender"),
                .product(name: "MosaicSettings", package: "MosaicSettings"),
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MosaicSwiftRenderUITests",
            dependencies: ["MosaicSwiftRenderUI"]
        ),
    ]
)
