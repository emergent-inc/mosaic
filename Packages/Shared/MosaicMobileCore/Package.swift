// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileCore",
            targets: ["MosaicMobileCore"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicMobileCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MosaicMobileCoreTests",
            dependencies: ["MosaicMobileCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
