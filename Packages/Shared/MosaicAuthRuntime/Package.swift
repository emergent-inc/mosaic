// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicAuthRuntime",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAuthRuntime",
            targets: ["MosaicAuthRuntime"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicAuthCore"),
        .package(path: "../../../vendor/stack-auth-swift-sdk-prerelease"),
    ],
    targets: [
        .target(
            name: "MosaicAuthRuntime",
            dependencies: [
                "MosaicAuthCore",
                .product(name: "StackAuth", package: "stack-auth-swift-sdk-prerelease"),
            ],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicAuthRuntimeTests",
            dependencies: ["MosaicAuthRuntime"],
            swiftSettings: [
                .define("MOSAIC_DEV_AUTH", .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
