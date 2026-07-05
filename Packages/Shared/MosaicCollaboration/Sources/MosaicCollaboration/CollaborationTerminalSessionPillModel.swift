/// Presentation model for the terminal-header session pill.
///
/// Before a session exists the pill shows the "Start session" call to action.
/// Once the workspace has a session, the pill collapses to a people icon plus
/// the total number of people in the session.
public struct CollaborationTerminalSessionPillModel: Equatable, Sendable {
    /// Whether the workspace has an active session (created or joined).
    public let hasSession: Bool
    /// Total participants in the session, including the local user.
    public let totalParticipantCount: Int
    /// Pending directory-share invites in the local user's inbox. Surfaced as a
    /// badge on the pill regardless of whether a session exists, so an incoming
    /// invite is visible without opening the popover.
    public let incomingInviteCount: Int

    /// Creates a pill model.
    /// - Parameters:
    ///   - workspaceSessionCode: The workspace's session code, `nil` when no
    ///     session exists.
    ///   - participantCount: Total participants including the local user
    ///     (the shape returned by the runtime's participant snapshots).
    ///   - incomingInviteCount: Pending invites in the local user's inbox.
    public init(
        workspaceSessionCode: String?,
        participantCount: Int,
        incomingInviteCount: Int = 0
    ) {
        self.hasSession = workspaceSessionCode != nil
        self.totalParticipantCount = hasSession ? max(participantCount, 0) : 0
        self.incomingInviteCount = max(incomingInviteCount, 0)
    }

    /// Whether the pill shows the participant count instead of the
    /// "Start session" label.
    public var showsParticipantCount: Bool { hasSession }

    /// Whether the pill should render an incoming-invite badge.
    public var showsIncomingBadge: Bool { incomingInviteCount > 0 }
}
