import Foundation

@_spi(MosaicHostTransport)
/// Host-side callbacks used by the sidebar XPC bridge.
public struct MosaicSidebarHostClient: Sendable {
    /// Returns the latest host snapshot that should be sent to an extension.
    public var snapshot: @Sendable () async throws -> MosaicSidebarSnapshot

    /// Dispatches a sidebar action from an extension into MOSAIC.
    public var dispatch: @Sendable (MosaicSidebarAction) async throws -> MosaicSidebarActionResult

    /// Creates a host client from snapshot and action-dispatch closures.
    public init(
        snapshot: @escaping @Sendable () async throws -> MosaicSidebarSnapshot,
        dispatch: @escaping @Sendable (MosaicSidebarAction) async throws -> MosaicSidebarActionResult
    ) {
        self.snapshot = snapshot
        self.dispatch = dispatch
    }
}
