// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicMobileDiagnostics",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileDiagnostics",
            targets: ["MosaicMobileDiagnostics"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicMobileDiagnostics",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileDiagnosticsTests",
            dependencies: ["MosaicMobileDiagnostics"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
