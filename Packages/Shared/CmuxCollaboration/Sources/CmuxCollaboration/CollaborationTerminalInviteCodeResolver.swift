public import Foundation

/// Resolves an invite code for terminals hosted by the local peer.
public struct CollaborationTerminalInviteCodeResolver: Equatable, Sendable {
    private let hostedTerminalIDsBySurfaceID: [UUID: String]
    private let terminalSessionRouter: CollaborationTerminalSessionRouter

    public init(
        hostedTerminalIDsBySurfaceID: [UUID: String],
        terminalSessionRouter: CollaborationTerminalSessionRouter
    ) {
        self.hostedTerminalIDsBySurfaceID = hostedTerminalIDsBySurfaceID
        self.terminalSessionRouter = terminalSessionRouter
    }

    /// Returns the owning session code only when the surface is a locally hosted terminal.
    public func inviteCode(forHostedSurfaceID surfaceID: UUID) -> String? {
        guard let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] else { return nil }
        return terminalSessionRouter.sessionCode(forTerminalID: terminalID)
    }
}
