// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileTerminalKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileTerminalKit",
            targets: ["MosaicMobileTerminalKit"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
    ],
    targets: [
        .target(
            name: "MosaicMobileTerminalKit",
            dependencies: [
                "MosaicMobileCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileTerminalKitTests",
            dependencies: ["MosaicMobileTerminalKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
