// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileShell",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileShell",
            targets: ["MosaicMobileShell"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../../Shared/MosaicAgentChat"),
        .package(path: "../MosaicMobileDiagnostics"),
        .package(path: "../MosaicMobilePairedMac"),
        .package(path: "../MosaicMobileRPC"),
        .package(path: "../MosaicMobileShellModel"),
        .package(path: "../MosaicMobileSupport"),
        .package(path: "../MosaicMobileTransport"),
    ],
    targets: [
        .target(
            name: "MosaicMobileShell",
            dependencies: [
                "MosaicMobileCore",
                "MosaicAgentChat",
                "MosaicMobileDiagnostics",
                "MosaicMobilePairedMac",
                "MosaicMobileRPC",
                "MosaicMobileShellModel",
                "MosaicMobileSupport",
                "MosaicMobileTransport",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileShellTests",
            dependencies: [
                "MosaicMobileShell",
                "MosaicMobileCore",
                "MosaicAgentChat",
                "MosaicMobilePairedMac",
                "MosaicMobileRPC",
                "MosaicMobileShellModel",
                "MosaicMobileTransport",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
