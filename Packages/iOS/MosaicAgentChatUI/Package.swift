// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicAgentChatUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAgentChatUI",
            targets: ["MosaicAgentChatUI"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicAgentChat"),
        .package(path: "../MosaicMobileSupport"),
    ],
    targets: [
        .target(
            name: "MosaicAgentChatUI",
            dependencies: [
                "MosaicAgentChat",
                "MosaicMobileSupport",
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MosaicAgentChatUITests",
            dependencies: ["MosaicAgentChatUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
