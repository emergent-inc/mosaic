// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicSidebarInterpreterService",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Host-side client + wire protocol the app links against.
        .library(
            name: "MosaicSidebarInterpreterClient",
            targets: ["MosaicSidebarInterpreterClient"]
        ),
        // The out-of-process worker that runs the untrusted interpreter.
        .executable(
            name: "mosaic-sidebar-interpreter",
            targets: ["mosaic-sidebar-interpreter"]
        ),
        // Headless protocol fixture for RenderWorkerClient supervision tests.
        .executable(
            name: "mosaic-sidebar-render-fixture",
            targets: ["mosaic-sidebar-render-fixture"]
        ),
        // Remote rendering: the faceless render-worker loop and the host-side
        // layer-hosting sidebar surface.
        .library(
            name: "MosaicSidebarRemoteRender",
            targets: ["MosaicSidebarRemoteRender"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicSwiftRender"),
        .package(path: "../MosaicSwiftRenderUI"),
    ],
    targets: [
        .target(
            name: "MosaicSidebarInterpreterClient",
            dependencies: ["MosaicSwiftRender"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "mosaic-sidebar-interpreter",
            dependencies: ["MosaicSidebarInterpreterClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "mosaic-sidebar-render-fixture",
            dependencies: ["MosaicSidebarInterpreterClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "MosaicSidebarRemoteRender",
            dependencies: [
                "MosaicSidebarInterpreterClient",
                .product(name: "MosaicSwiftRenderUI", package: "MosaicSwiftRenderUI"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MosaicSidebarInterpreterClientTests",
            dependencies: ["MosaicSidebarInterpreterClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MosaicSidebarRemoteRenderTests",
            dependencies: ["MosaicSidebarRemoteRender"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
