// swift-tools-version: 6.0

import PackageDescription

// `mosaicFeature` is the iOS composition-root package, not a catch-all. After the
// 5079 refactor it holds only the runtime DI bundle (`MosaicMobileRuntime`), the
// auth composition (`MobileAuthComposition` over `MosaicAuthRuntime`), and the
// root scene (`MosaicMobileRootScene`). The store, RPC, persistence, terminal,
// and view code were lifted into the focused packages it depends on below. See
// README.md for the per-type role table.
let package = Package(
    name: "mosaicFeature",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "mosaicFeature",
            targets: ["mosaicFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../../Packages/Shared/MosaicAuthCore"),
        .package(path: "../../Packages/Shared/MosaicAuthRuntime"),
        .package(path: "../../Packages/Shared/MosaicMobileCore"),
        .package(path: "../../Packages/iOS/MosaicMobileAnalytics"),
        .package(path: "../../Packages/iOS/MosaicMobileBrowser"),
        .package(path: "../../Packages/iOS/MosaicMobileCamera"),
        .package(path: "../../Packages/iOS/MosaicMobileDiagnostics"),
        .package(path: "../../Packages/iOS/MosaicMobilePairedMac"),
        .package(path: "../../Packages/iOS/MosaicMobileRPC"),
        .package(path: "../../Packages/iOS/MosaicMobileShell"),
        .package(path: "../../Packages/iOS/MosaicMobileShellModel"),
        .package(path: "../../Packages/iOS/MosaicMobileShellUI"),
        .package(path: "../../Packages/iOS/MosaicMobileSupport"),
        .package(path: "../../Packages/iOS/MosaicMobileTerminal"),
        .package(path: "../../Packages/iOS/MosaicMobileTerminalKit"),
        .package(path: "../../Packages/iOS/MosaicMobileTransport"),
        .package(path: "../../Packages/iOS/MosaicMobileWorkspace"),
        .package(path: "../../vendor/stack-auth-swift-sdk-prerelease"),
    ],
    targets: [
        .target(
            name: "mosaicFeature",
            dependencies: [
                "MosaicAuthCore",
                "MosaicAuthRuntime",
                "MosaicMobileCore",
                "MosaicMobileAnalytics",
                "MosaicMobileBrowser",
                "MosaicMobileCamera",
                "MosaicMobileDiagnostics",
                "MosaicMobilePairedMac",
                "MosaicMobileRPC",
                "MosaicMobileShell",
                "MosaicMobileShellModel",
                "MosaicMobileShellUI",
                "MosaicMobileSupport",
                "MosaicMobileTerminal",
                "MosaicMobileTerminalKit",
                "MosaicMobileTransport",
                "MosaicMobileWorkspace",
                .product(name: "StackAuth", package: "stack-auth-swift-sdk-prerelease"),
            ],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "mosaicFeatureTests",
            dependencies: [
                "mosaicFeature",
                "MosaicAuthCore",
                "MosaicAuthRuntime",
                "MosaicMobileCore",
                "MosaicMobileAnalytics",
                "MosaicMobileBrowser",
                "MosaicMobileCamera",
                "MosaicMobileDiagnostics",
                "MosaicMobilePairedMac",
                "MosaicMobileRPC",
                "MosaicMobileShell",
                "MosaicMobileShellModel",
                "MosaicMobileShellUI",
                "MosaicMobileSupport",
                "MosaicMobileTerminal",
                "MosaicMobileTerminalKit",
                "MosaicMobileTransport",
                "MosaicMobileWorkspace",
                .product(name: "StackAuth", package: "stack-auth-swift-sdk-prerelease"),
            ],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
            ]
        ),
    ]
)
