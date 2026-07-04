// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicWindowing",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicWindowing",
            targets: ["MosaicWindowing"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicWindowing",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicWindowingTests",
            dependencies: ["MosaicWindowing"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
