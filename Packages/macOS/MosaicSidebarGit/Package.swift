// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSidebarGit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSidebarGit",
            targets: ["MosaicSidebarGit"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicGit"),
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicSidebarGit",
            dependencies: [
                .product(name: "MosaicGit", package: "MosaicGit"),
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicSidebarGitTests",
            dependencies: [
                "MosaicSidebarGit",
                .product(name: "MosaicGit", package: "MosaicGit"),
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
