import Foundation

/// Current sidebar state delivered by MOSAIC to a sidebar extension.
public struct MosaicSidebarContext: Sendable {
    /// Latest workspace snapshot filtered to the permissions granted by the user.
    public let snapshot: MosaicSidebarSnapshot

    /// Read scopes MOSAIC granted for this snapshot.
    public let grantedReadScopes: Set<MosaicExtensionScope>

    /// Host actions MOSAIC will currently accept from this extension.
    public let grantedActionScopes: Set<MosaicExtensionActionScope>

    /// Typed command channel back to MOSAIC.
    public let host: MosaicSidebarHost

    @MainActor
    public init(
        snapshot: MosaicSidebarSnapshot,
        grantedReadScopes: Set<MosaicExtensionScope>? = nil,
        grantedActionScopes: Set<MosaicExtensionActionScope>? = nil,
        host: MosaicSidebarHost
    ) {
        self.snapshot = snapshot
        self.grantedReadScopes = grantedReadScopes ?? snapshot.grantedReadScopes
        self.grantedActionScopes = grantedActionScopes ?? snapshot.grantedActionScopes
        self.host = host
    }
}
