// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicAppKitSupportUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAppKitSupportUI",
            targets: ["MosaicAppKitSupportUI"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicWorkspaces"),
    ],
    targets: [
        .target(
            name: "MosaicAppKitSupportUI",
            dependencies: [
                "MosaicFoundation",
                "MosaicWorkspaces",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicAppKitSupportUITests",
            dependencies: ["MosaicAppKitSupportUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
