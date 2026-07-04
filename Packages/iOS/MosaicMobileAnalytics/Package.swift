// swift-tools-version: 6.0

import PackageDescription

// `MosaicMobileAnalytics` is the concrete analytics infrastructure: the
// fire-and-forget `AnalyticsEmitter` actor, the pure sessionization and
// connection-edge throttle logic, and the HTTP capture client that posts batches
// to the mosaic web analytics proxy. It conforms to the `AnalyticsEmitting` seam
// declared in `MosaicMobileCore`, so it depends only on that base package and
// Foundation — keeping the package graph an acyclic DAG. Everything it touches
// (the opt-out gate, the clock, `UserDefaults`, reachability, the base URL) is
// injected at construction so the actor is testable without the app.
let package = Package(
    name: "MosaicMobileAnalytics",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicMobileAnalytics",
            targets: ["MosaicMobileAnalytics"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/MosaicMobileCore"),
    ],
    targets: [
        .target(
            name: "MosaicMobileAnalytics",
            dependencies: [
                "MosaicMobileCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicMobileAnalyticsTests",
            dependencies: ["MosaicMobileAnalytics"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
