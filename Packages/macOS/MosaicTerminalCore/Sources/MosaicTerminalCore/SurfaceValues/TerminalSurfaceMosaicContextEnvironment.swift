public import Foundation

/// The managed mosaic context identity exported to a spawned terminal process.
///
/// These values become the `MOSAIC_WORKSPACE_ID` / `MOSAIC_SURFACE_ID` /
/// `MOSAIC_SOCKET_PATH` (and legacy tab/panel alias) environment variables.
public struct TerminalSurfaceMosaicContextEnvironment: Equatable, Sendable {
    /// The owning workspace id (exported as `MOSAIC_WORKSPACE_ID` / `MOSAIC_TAB_ID`).
    public let workspaceId: UUID

    /// The surface id (exported as `MOSAIC_SURFACE_ID` / `MOSAIC_PANEL_ID`).
    public let surfaceId: UUID

    /// The control socket path (exported as `MOSAIC_SOCKET_PATH`).
    public let socketPath: String

    /// Creates the managed context identity.
    ///
    /// - Parameters:
    ///   - workspaceId: The owning workspace id.
    ///   - surfaceId: The surface id.
    ///   - socketPath: The control socket path.
    public init(workspaceId: UUID, surfaceId: UUID, socketPath: String) {
        self.workspaceId = workspaceId
        self.surfaceId = surfaceId
        self.socketPath = socketPath
    }
}
