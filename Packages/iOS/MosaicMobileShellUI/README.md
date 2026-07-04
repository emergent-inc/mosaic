# MosaicMobileShellUI

The SwiftUI half of the mosaic iOS shell.

This is the leaf UI layer extracted out of the `mosaicFeature` catch-all target. It
owns the workspace shell, sign-in, pairing, terminal detail, and root routing
views, plus the iOS push coordinator that the root view injects into the
SwiftUI environment.

It depends only downward: the decomposed domain facade
(`MosaicMobileShell.MosaicMobileShellStore`), the core/value packages
(`MosaicMobileCore`, `MosaicMobileShellModel`, `MosaicMobileWorkspace`,
`MosaicMobileSupport`), `MosaicAuthRuntime` for the injected `AuthCoordinator`,
`MosaicMobileTerminal` for the libghostty surface, and `MosaicMobileCamera` for the
QR-pairing capture stack. It never reaches into RPC/transport concretes.

`mosaicFeature` now sits *above* this package as the composition root
(`MosaicMobileRootScene`, `MosaicMobileRuntime`, the auth/push wiring) and
re-exports the package so the app shell keeps `import mosaicFeature` working.

## Entry points

- ``MosaicMobileAppView`` — the live mobile UI root, mounted by `MosaicMobileRootScene`.
- ``MobilePushCoordinator`` — APNs↔store bridge, constructed at the app root.
