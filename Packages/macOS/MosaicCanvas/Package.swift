// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicCanvas",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MosaicCanvas",
            targets: ["MosaicCanvas"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicCanvas",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicCanvasTests",
            dependencies: [
                "MosaicCanvas",
            ]
        ),
    ]
)
