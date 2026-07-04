// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicPanes",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicPanes",
            targets: ["MosaicPanes"]
        ),
    ],
    dependencies: [
        .package(path: "../../../vendor/bonsplit"),
    ],
    targets: [
        .target(
            name: "MosaicPanes",
            dependencies: [
                .product(name: "Bonsplit", package: "bonsplit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicPanesTests",
            dependencies: ["MosaicPanes"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
