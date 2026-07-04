// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicFoundation",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicFoundation",
            targets: ["MosaicFoundation"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicFoundation",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicFoundationTests",
            dependencies: ["MosaicFoundation"]
        ),
    ]
)
