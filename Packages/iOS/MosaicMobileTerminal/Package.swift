// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileTerminal",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "MosaicMobileTerminal",
            targets: ["MosaicMobileTerminal"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
        .package(path: "../MosaicMobileDiagnostics"),
        .package(path: "../MosaicMobileSupport"),
        .package(path: "../MosaicMobileTerminalKit"),
    ],
    targets: [
        // The same libghostty the Mac links; iOS feeds raw PTY bytes straight
        // into ghostty_surface_* so the phone runs the identical terminal core.
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../../GhosttyKit.xcframework"
        ),
        .target(
            name: "MosaicMobileTerminal",
            dependencies: [
                "MosaicMobileCore",
                "MosaicMobileDiagnostics",
                "MosaicMobileSupport",
                "MosaicMobileTerminalKit",
                "GhosttyKit",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
