// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicControlSocket",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicControlSocket",
            targets: ["MosaicControlSocket"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicSettings"),
    ],
    targets: [
        .target(
            name: "MosaicControlSocket",
            dependencies: [
                .product(name: "MosaicSettings", package: "MosaicSettings"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicControlSocketTests",
            dependencies: [
                "MosaicControlSocket",
                .product(name: "MosaicSettings", package: "MosaicSettings"),
            ]
        ),
    ]
)
