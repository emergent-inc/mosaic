// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSyncStore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSyncStore",
            targets: ["MosaicSyncStore"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicMobileCore"),
        .package(path: "../../iOS/MosaicMobilePairedMac"),
        .package(path: "../../iOS/MosaicMobileShellModel"),
    ],
    targets: [
        .target(
            name: "MosaicSyncStore",
            dependencies: [
                "MosaicMobileCore",
                "MosaicMobilePairedMac",
                "MosaicMobileShellModel",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicSyncStoreTests",
            dependencies: ["MosaicSyncStore", "MosaicMobilePairedMac", "MosaicMobileCore", "MosaicMobileShellModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
