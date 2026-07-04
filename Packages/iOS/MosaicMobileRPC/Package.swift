// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileRPC",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileRPC",
            targets: ["MosaicMobileRPC"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../MosaicMobileShellModel"),
        .package(path: "../MosaicMobileSupport"),
    ],
    targets: [
        .target(
            name: "MosaicMobileRPC",
            dependencies: [
                "MosaicMobileCore",
                "MosaicMobileShellModel",
                "MosaicMobileSupport",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileRPCTests",
            dependencies: [
                "MosaicMobileRPC",
                "MosaicMobileCore",
                "MosaicMobileShellModel",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
