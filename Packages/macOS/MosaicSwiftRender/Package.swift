// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSwiftRender",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSwiftRender",
            targets: ["MosaicSwiftRender"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "MosaicSwiftRender",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MosaicSwiftRenderTests",
            dependencies: ["MosaicSwiftRender"],
            // Corpus holds sidebar DSL files (interpreter input, not test code).
            exclude: ["Corpus"]
        ),
    ]
)
