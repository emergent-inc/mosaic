import MosaicTerminalCore

/// Lets `MosaicConfigStoreReloadCoordinator` drive per-window config reloads through a
/// protocol seam. `MosaicConfigStore`'s existing `loadAll()` already satisfies the
/// requirement, so this conformance is empty.
extension MosaicConfigStore: MosaicConfigStoreReloading {}
