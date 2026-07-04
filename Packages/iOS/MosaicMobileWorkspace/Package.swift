// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileWorkspace",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileWorkspace",
            targets: ["MosaicMobileWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../MosaicMobileShellModel"),
    ],
    targets: [
        .target(
            name: "MosaicMobileWorkspace",
            dependencies: [
                "MosaicMobileCore",
                "MosaicMobileShellModel",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileWorkspaceTests",
            dependencies: ["MosaicMobileWorkspace"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
