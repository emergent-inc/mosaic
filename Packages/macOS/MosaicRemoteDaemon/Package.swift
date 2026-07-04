// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicRemoteDaemon",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicRemoteDaemon",
            targets: ["MosaicRemoteDaemon"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicCore"),
    ],
    targets: [
        .target(
            name: "MosaicRemoteDaemon",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicCore", package: "MosaicCore"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicRemoteDaemonTests",
            dependencies: [
                "MosaicRemoteDaemon",
                .product(name: "MosaicCore", package: "MosaicCore"),
            ]
        ),
    ]
)
