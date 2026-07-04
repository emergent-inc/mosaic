// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileTransport",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileTransport",
            targets: ["MosaicMobileTransport"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
    ],
    targets: [
        .target(
            name: "MosaicMobileTransport",
            dependencies: ["MosaicMobileCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileTransportTests",
            dependencies: ["MosaicMobileTransport", "MosaicMobileCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
