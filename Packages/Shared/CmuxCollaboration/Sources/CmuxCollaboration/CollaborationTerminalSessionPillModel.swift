/// Presentation model for the terminal-header session pill.
///
/// Before a session exists the pill shows the "Start session" call to action.
/// Once the workspace has a session, the pill collapses to a people icon plus
/// the number of *other* people in the session (the local user is always a
/// participant, so a freshly created session shows `0`).
public struct CollaborationTerminalSessionPillModel: Equatable, Sendable {
    /// Whether the workspace has an active session (created or joined).
    public let hasSession: Bool
    /// How many people besides the local user are in the session.
    public let otherParticipantCount: Int

    /// Creates a pill model.
    /// - Parameters:
    ///   - workspaceSessionCode: The workspace's session code, `nil` when no
    ///     session exists.
    ///   - participantCount: Total participants including the local user
    ///     (the shape returned by the runtime's participant snapshots).
    public init(workspaceSessionCode: String?, participantCount: Int) {
        self.hasSession = workspaceSessionCode != nil
        self.otherParticipantCount = hasSession ? max(participantCount - 1, 0) : 0
    }

    /// Whether the pill shows the participant count instead of the
    /// "Start session" label.
    public var showsParticipantCount: Bool { hasSession }
}
