// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicAgentChat",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAgentChat",
            targets: ["MosaicAgentChat"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicAgentChat",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MosaicAgentChatTests",
            dependencies: ["MosaicAgentChat"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
