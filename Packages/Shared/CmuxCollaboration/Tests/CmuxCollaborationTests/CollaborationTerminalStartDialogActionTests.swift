import CmuxCollaboration
import Testing

struct CollaborationTerminalStartDialogActionTests {
    @Test(arguments: [
        (buttonIndex: 1, action: CollaborationTerminalStartDialogAction.createSessionAndShareTerminal),
        (buttonIndex: 2, action: CollaborationTerminalStartDialogAction.joinSessionAndBindWorkspace),
        (buttonIndex: 0, action: CollaborationTerminalStartDialogAction.cancel),
        (buttonIndex: 3, action: CollaborationTerminalStartDialogAction.cancel),
    ])
    func terminalStartDialogButtonsMapToCreateShareJoinBindOrCancel(
        buttonIndex: Int,
        action: CollaborationTerminalStartDialogAction
    ) {
        #expect(CollaborationTerminalStartDialogAction.action(buttonIndex: buttonIndex) == action)
    }
}
