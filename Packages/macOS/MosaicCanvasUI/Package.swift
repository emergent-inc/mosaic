// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicCanvasUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicCanvasUI",
            targets: ["MosaicCanvasUI"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicCanvas"),
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicCanvasUI",
            dependencies: [
                "MosaicCanvas",
                "MosaicFoundation",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicCanvasUITests",
            dependencies: [
                "MosaicCanvasUI",
            ]
        ),
    ]
)
