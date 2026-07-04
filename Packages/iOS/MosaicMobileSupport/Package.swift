// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileSupport",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileSupport",
            targets: ["MosaicMobileSupport"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicMobileSupport",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileSupportTests",
            dependencies: ["MosaicMobileSupport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
