// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobilePairedMac",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobilePairedMac",
            targets: ["MosaicMobilePairedMac"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
    ],
    targets: [
        .target(
            name: "MosaicMobilePairedMac",
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
            name: "MosaicMobilePairedMacTests",
            dependencies: ["MosaicMobilePairedMac"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
