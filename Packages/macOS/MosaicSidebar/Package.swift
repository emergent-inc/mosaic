// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSidebar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSidebar",
            targets: ["MosaicSidebar"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicSwiftRender"),
        // MosaicExtensionKit backs the ExtensionHost/ sidebar-extension host view
        // and browser presenter.
        .package(path: "../MosaicExtensionKit"),
    ],
    targets: [
        .target(
            name: "MosaicSidebar",
            dependencies: [
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicSwiftRender", package: "MosaicSwiftRender"),
                .product(name: "MosaicExtensionKit", package: "MosaicExtensionKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicSidebarTests",
            dependencies: [
                "MosaicSidebar",
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicSwiftRender", package: "MosaicSwiftRender"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
