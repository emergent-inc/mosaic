// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicExtensionSidebarExamples",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MosaicExtensionSidebarExamples",
            targets: ["MosaicExtensionSidebarExamples"]
        ),
    ],
    dependencies: [
        .package(path: "../../Packages/macOS/MosaicSidebarProviderKit"),
    ],
    targets: [
        .target(
            name: "MosaicExtensionSidebarExamples",
            dependencies: ["MosaicSidebarProviderKit"]
        ),
        .testTarget(
            name: "MosaicExtensionSidebarExamplesTests",
            dependencies: ["MosaicExtensionSidebarExamples"]
        ),
    ]
)
