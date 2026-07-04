/// The terminal-specific action chosen from the collaboration start dialog.
public enum CollaborationTerminalStartDialogAction: Equatable, Sendable {
    /// Create a new session and share the clicked terminal as the host terminal.
    case createSessionAndShareTerminal
    /// Join an existing session and bind the workspace without sharing the clicked terminal.
    case joinSessionAndBindWorkspace
    /// Dismiss the dialog without changing collaboration state.
    case cancel

    /// Resolves a terminal start-dialog button index into a collaboration action.
    /// - Parameter buttonIndex: One-based button index matching AppKit alert button order.
    /// - Returns: The terminal-specific action for the selected button.
    public static func action(buttonIndex: Int) -> CollaborationTerminalStartDialogAction {
        switch buttonIndex {
        case 1:
            return .createSessionAndShareTerminal
        case 2:
            return .joinSessionAndBindWorkspace
        default:
            return .cancel
        }
    }
}
