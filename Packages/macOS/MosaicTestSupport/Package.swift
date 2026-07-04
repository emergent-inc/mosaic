// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicTestSupport",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicTestSupport",
            targets: ["MosaicTestSupport"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicTestSupport",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicTestSupportTests",
            dependencies: ["MosaicTestSupport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
