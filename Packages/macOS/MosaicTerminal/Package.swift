// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicTerminal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicTerminal",
            targets: ["MosaicTerminal"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicTerminalCore"),
        .package(path: "../MosaicDebugLog"),
        .package(path: "../MosaicAgentLaunch"),
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../../../vendor/bonsplit"),
    ],
    targets: [
        .target(
            name: "MosaicTerminal",
            dependencies: [
                .product(name: "MosaicTerminalCore", package: "MosaicTerminalCore"),
                .product(name: "MosaicGhosttyKit", package: "MosaicTerminalCore"),
                .product(name: "MosaicDebugLog", package: "MosaicDebugLog"),
                .product(name: "MosaicAgentLaunch", package: "MosaicAgentLaunch"),
                .product(name: "MosaicMobileCore", package: "MosaicMobileCore"),
                .product(name: "Bonsplit", package: "bonsplit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        // Test-only stand-in for the @_silgen_name libghostty symbol bound by
        // MosaicTerminalCore's GhosttyRuntimeCInterop: SwiftPM cannot link the
        // GhosttyKit macOS archive (its binary lacks the lib prefix), so the
        // test runner satisfies the link with a stub. The app links the real
        // GhosttyKit.
        .target(
            name: "GhosttyRuntimeTestStubs",
            path: "Tests/GhosttyRuntimeTestStubs"
        ),
        .testTarget(
            name: "MosaicTerminalTests",
            dependencies: [
                "MosaicTerminal",
                "GhosttyRuntimeTestStubs",
                .product(name: "MosaicTerminalCore", package: "MosaicTerminalCore"),
                .product(name: "MosaicGhosttyKit", package: "MosaicTerminalCore"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
