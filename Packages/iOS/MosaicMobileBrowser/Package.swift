// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileBrowser",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileBrowser",
            targets: ["MosaicMobileBrowser"]
        ),
    ],
    dependencies: [
        // Localized-string helpers (`L10n`). `MosaicMobileSupport` is a leaf with
        // no dependencies, so the browser package stays low in the DAG.
        .package(path: "../MosaicMobileSupport"),
    ],
    targets: [
        // A self-contained, phone-local browser surface. P1 browser state never
        // touches the Mac, so this package sits low in the DAG: it depends only
        // on the leaf `MosaicMobileSupport` and links Foundation/WebKit/SwiftUI.
        .target(
            name: "MosaicMobileBrowser",
            dependencies: [
                "MosaicMobileSupport",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileBrowserTests",
            dependencies: ["MosaicMobileBrowser"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
