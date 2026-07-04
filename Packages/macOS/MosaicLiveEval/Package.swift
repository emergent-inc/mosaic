// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicLiveEval",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicLiveEval",
            targets: ["MosaicLiveEval"]
        ),
        .executable(
            name: "LiveEvalDemo",
            targets: ["LiveEvalDemo"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicSwiftRender"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "MosaicLiveEval",
            dependencies: [
                .product(name: "MosaicSwiftRender", package: "MosaicSwiftRender"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "LiveEvalDemo",
            dependencies: ["MosaicLiveEval"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MosaicLiveEvalTests",
            dependencies: ["MosaicLiveEval"]
        ),
    ]
)
