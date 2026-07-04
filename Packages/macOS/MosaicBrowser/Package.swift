// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicBrowser",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicBrowser",
            targets: ["MosaicBrowser"]
        ),
    ],
    dependencies: [
        .package(path: "../../../vendor/bonsplit"),
    ],
    targets: [
        .target(
            name: "MosaicBrowser",
            dependencies: [
                .product(name: "Bonsplit", package: "bonsplit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicBrowserTests",
            dependencies: ["MosaicBrowser"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
