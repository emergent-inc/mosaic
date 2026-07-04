// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicRemoteWorkspace",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicRemoteWorkspace",
            targets: ["MosaicRemoteWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicCore"),
        .package(path: "../MosaicRemoteDaemon"),
        .package(path: "../MosaicSettings"),
    ],
    targets: [
        .target(
            name: "MosaicRemoteWorkspace",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicCore", package: "MosaicCore"),
                .product(name: "MosaicRemoteDaemon", package: "MosaicRemoteDaemon"),
                .product(name: "MosaicSettings", package: "MosaicSettings"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicRemoteWorkspaceTests",
            dependencies: ["MosaicRemoteWorkspace"]
        ),
    ]
)
