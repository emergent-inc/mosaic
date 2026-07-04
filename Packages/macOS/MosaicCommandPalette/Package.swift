// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicCommandPalette",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicCommandPalette",
            targets: ["MosaicCommandPalette"]
        ),
    ],
    dependencies: [
        // MosaicFoundation backs the FocusGuards/ command-palette focus-stealing
        // NSResponder/NSView guards.
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicCommandPalette",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicCommandPaletteTests",
            dependencies: [
                "MosaicCommandPalette",
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
