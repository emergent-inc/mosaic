// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicUpdaterUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicUpdaterUI",
            targets: ["MosaicUpdaterUI"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicUpdater"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "MosaicUpdaterUI",
            dependencies: [
                "MosaicFoundation",
                "MosaicUpdater",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicUpdaterUITests",
            dependencies: ["MosaicUpdaterUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
