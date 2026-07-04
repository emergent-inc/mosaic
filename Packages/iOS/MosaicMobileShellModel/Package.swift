// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileShellModel",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileShellModel",
            targets: ["MosaicMobileShellModel"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
    ],
    targets: [
        .target(
            name: "MosaicMobileShellModel",
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
            name: "MosaicMobileShellModelTests",
            dependencies: ["MosaicMobileShellModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
