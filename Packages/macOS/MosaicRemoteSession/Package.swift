// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicRemoteSession",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicRemoteSession",
            targets: ["MosaicRemoteSession"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicCore"),
        .package(path: "../MosaicRemoteDaemon"),
        .package(path: "../MosaicRemoteWorkspace"),
        .package(path: "../MosaicDebugLog"),
    ],
    targets: [
        .target(
            name: "MosaicRemoteSession",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicCore", package: "MosaicCore"),
                .product(name: "MosaicRemoteDaemon", package: "MosaicRemoteDaemon"),
                .product(name: "MosaicRemoteWorkspace", package: "MosaicRemoteWorkspace"),
                .product(name: "MosaicDebugLog", package: "MosaicDebugLog"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicRemoteSessionTests",
            dependencies: [
                "MosaicRemoteSession",
                .product(name: "MosaicCore", package: "MosaicCore"),
                .product(name: "MosaicRemoteDaemon", package: "MosaicRemoteDaemon"),
                .product(name: "MosaicRemoteWorkspace", package: "MosaicRemoteWorkspace"),
            ]
        ),
    ]
)
