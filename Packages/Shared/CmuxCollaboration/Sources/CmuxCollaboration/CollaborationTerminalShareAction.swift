/// The next action for a terminal collaboration button press.
public enum CollaborationTerminalShareAction: Equatable, Sendable {
    /// Show the create, join, or rejoin session chooser.
    case presentSessionChooser
    /// Rejoin the collaboration session already assigned to this workspace.
    case rejoinWorkspaceSession
    /// Show the recipient picker for the terminal that is already connected to a session.
    case presentParticipantPicker

    /// Resolves the action for the current terminal state.
    /// - Parameters:
    ///   - isShared: Whether the terminal is already shared in any session.
    ///   - workspaceHasSession: Whether the terminal's workspace already owns a session.
    /// - Returns: The action the peer button should perform.
    public static func action(
        isShared: Bool,
        workspaceHasSession: Bool = false
    ) -> CollaborationTerminalShareAction {
        if isShared {
            return .presentParticipantPicker
        }
        return workspaceHasSession ? .rejoinWorkspaceSession : .presentSessionChooser
    }
}
