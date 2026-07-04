# MosaicSidebarProviderKit

Internal app-side kit for mosaic-owned sidebar providers.

Use this package for in-process sidebar render models, sidebar provider descriptors, and provider mutations that run inside the mosaic app. It is not the public extension SDK for third-party sidebar app extensions, and all types use `MosaicSidebarProvider` naming to keep that boundary visible.

External extension authors should import `MosaicExtensionKit` instead.
