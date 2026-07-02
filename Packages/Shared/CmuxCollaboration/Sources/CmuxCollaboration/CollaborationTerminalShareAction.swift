/// The next action for a terminal collaboration button press.
public enum CollaborationTerminalShareAction: Equatable, Sendable {
    /// Show the create, join, or rejoin session chooser.
    case presentSessionChooser
    /// Stop sharing the terminal that is already connected to a session.
    case leaveSharedTerminal

    /// Resolves the action for the current terminal state.
    /// - Parameter isShared: Whether the terminal is already shared in any session.
    /// - Returns: The action the peer button should perform.
    public static func action(isShared: Bool) -> CollaborationTerminalShareAction {
        isShared ? .leaveSharedTerminal : .presentSessionChooser
    }
}
