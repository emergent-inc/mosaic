// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicTerminalCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicTerminalCore",
            targets: ["MosaicTerminalCore"]
        ),
        // Re-vends the GhosttyKit binaryTarget so the MosaicTerminal runtime
        // package can implement seam protocols whose signatures use ghostty C
        // types, without declaring a duplicate binary target for the one
        // xcframework.
        .library(
            name: "MosaicGhosttyKit",
            targets: ["GhosttyKit"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
        .package(path: "../MosaicDebugLog"),
    ],
    targets: [
        // The same libghostty the app links; the terminal core's value types and
        // FFI seam speak the ghostty C types directly so no translation layer
        // can drift from the runtime.
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../../GhosttyKit.xcframework"
        ),
        .target(
            name: "MosaicTerminalCore",
            dependencies: [
                "GhosttyKit",
                .product(name: "MosaicFoundation", package: "MosaicFoundation"),
                .product(name: "MosaicDebugLog", package: "MosaicDebugLog"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        // Test-only stand-in for the @_silgen_name libghostty symbol bound by
        // GhosttyRuntimeCInterop: SwiftPM cannot link the GhosttyKit macOS
        // archive (its binary lacks the lib prefix), so the test runner
        // satisfies the link with a stub. The app links the real GhosttyKit.
        .target(
            name: "GhosttyRuntimeTestStubs",
            path: "Tests/GhosttyRuntimeTestStubs"
        ),
        .testTarget(
            name: "MosaicTerminalCoreTests",
            dependencies: [
                "MosaicTerminalCore",
                "GhosttyRuntimeTestStubs",
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
