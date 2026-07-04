// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileShellUI",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "MosaicMobileShellUI",
            targets: ["MosaicMobileShellUI"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../../Shared/MosaicAgentChat"),
        .package(path: "../MosaicAgentChatUI"),
        .package(path: "../../Shared/MosaicAuthRuntime"),
        .package(path: "../MosaicMobileBrowser"),
        .package(path: "../MosaicMobileCamera"),
        .package(path: "../MosaicMobileDiagnostics"),
        .package(path: "../MosaicMobilePairedMac"),
        .package(path: "../MosaicMobileShell"),
        .package(path: "../MosaicMobileShellModel"),
        .package(path: "../MosaicMobileSupport"),
        .package(path: "../MosaicMobileTerminal"),
        .package(path: "../MosaicMobileTerminalKit"),
        .package(path: "../MosaicMobileWorkspace"),
        .package(path: "../../../vendor/stack-auth-swift-sdk-prerelease"),
    ],
    targets: [
        .target(
            name: "MosaicMobileShellUI",
            dependencies: [
                "MosaicMobileCore",
                "MosaicAgentChat",
                "MosaicAgentChatUI",
                "MosaicAuthRuntime",
                "MosaicMobileBrowser",
                "MosaicMobileCamera",
                "MosaicMobileDiagnostics",
                "MosaicMobilePairedMac",
                "MosaicMobileShell",
                "MosaicMobileShellModel",
                "MosaicMobileSupport",
                "MosaicMobileTerminal",
                "MosaicMobileTerminalKit",
                "MosaicMobileWorkspace",
                .product(name: "StackAuth", package: "stack-auth-swift-sdk-prerelease"),
            ],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MosaicMobileShellUITests",
            dependencies: [
                "MosaicMobileCore",
                "MosaicMobilePairedMac",
                "MosaicMobileShellUI",
                "MosaicAgentChat",
                "MosaicMobileShell",
                "MosaicMobileShellModel",
                "MosaicMobileWorkspace",
                .product(name: "StackAuth", package: "stack-auth-swift-sdk-prerelease"),
            ],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
