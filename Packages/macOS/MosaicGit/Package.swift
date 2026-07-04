// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicGit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicGit",
            targets: ["MosaicGit"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicGit",
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
            name: "MosaicGitTests",
            dependencies: ["MosaicGit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
