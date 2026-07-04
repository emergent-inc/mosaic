// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileCamera",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileCamera",
            targets: ["MosaicMobileCamera"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicMobileCamera",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileCameraTests",
            dependencies: ["MosaicMobileCamera"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
