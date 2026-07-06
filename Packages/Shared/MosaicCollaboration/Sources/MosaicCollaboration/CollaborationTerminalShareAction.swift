/// The next action for a terminal sharing control.
public enum CollaborationTerminalShareAction: Equatable, Sendable {
    /// Show the create or join session chooser before sharing can start.
    case presentSessionChooser
    /// Create a session silently and share the terminal without any chooser
    /// dialog (team/enterprise directory-sharing plans: the session is an
    /// implementation detail behind the teammate picker).
    case createSessionAndShareDirectly
    /// Share the local terminal in the workspace's existing session.
    case shareInWorkspaceSession
    /// Stop hosting the local terminal.
    case stopSharingHostedTerminal
    /// Stop viewing a mirrored remote terminal.
    case stopViewingRemoteTerminal
    /// Show the recipient picker for a hosted terminal.
    case presentParticipantPicker

    /// Resolves the primary sharing-control action for the current terminal state.
    /// - Parameters:
    ///   - role: Whether the terminal is not shared, hosted by this user, or mirrored from a collaborator.
    ///   - workspaceHasSession: Whether the terminal's workspace already owns a session.
    ///   - directorySharingEnabled: Whether the caller's org has directory ("no codes")
    ///     sharing, which skips the create-or-join chooser entirely.
    /// - Returns: The action the peer button should perform.
    public static func primaryAction(
        role: CollaborationSurfaceSharingRole,
        workspaceHasSession: Bool = false,
        directorySharingEnabled: Bool = false
    ) -> CollaborationTerminalShareAction {
        switch role {
        case .notShared:
            if workspaceHasSession {
                return .shareInWorkspaceSession
            }
            return directorySharingEnabled ? .createSessionAndShareDirectly : .presentSessionChooser
        case .hosted:
            return .stopSharingHostedTerminal
        case .mirrored:
            return .stopViewingRemoteTerminal
        }
    }

    /// Resolves the people-management action for the current terminal state.
    /// - Parameter role: Whether the terminal is not shared, hosted by this user, or mirrored from a collaborator.
    /// - Returns: The action available from the people button, when any.
    public static func managementAction(
        role: CollaborationSurfaceSharingRole
    ) -> CollaborationTerminalShareAction? {
        role == .hosted ? .presentParticipantPicker : nil
    }
}
