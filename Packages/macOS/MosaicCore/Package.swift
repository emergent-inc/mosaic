// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicCore",
            targets: ["MosaicCore"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicCore",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicCoreTests",
            dependencies: ["MosaicCore"]
        ),
    ]
)
