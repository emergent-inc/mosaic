import Foundation
import MosaicCollaboration
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

/// Regression coverage for guest-side terminal sharing.
///
/// When a guest joins a collaboration session (e.g. by accepting an inbox
/// invite), the host's shared terminal opens as a mirrored pane in one of the
/// guest's workspaces. Sharing one of the guest's own terminals from that
/// workspace must route into the joined session (`.shareInWorkspaceSession`),
/// not prompt the guest to create a brand-new session. That routing is driven
/// by the workspace -> session binding recorded during the mirror open; hosts
/// get the equivalent binding when they create the session.
@MainActor
@Suite struct CollaborationGuestWorkspaceBindingTests {
    @Test func mirroredTerminalOpenBindsGuestWorkspaceToJoinedSession() {
        let runtime = CollaborationRuntime.shared
        let workspaceID = UUID()
        // Eight significant characters: survives invite-code normalization
        // unchanged, matching real relay session codes.
        let sessionCode = "NXPLXZAH"
        defer { CollaborationWorkspaceSessionStore().remove(workspaceID: workspaceID) }

        runtime.recordMirroredTerminalSessionRouting(
            terminalID: "guest-mirrored-terminal-\(workspaceID.uuidString)",
            sessionCode: sessionCode,
            workspaceID: workspaceID
        )

        let boundCode = runtime.debugWorkspaceSessionCodeForTesting(workspaceID: workspaceID)
        #expect(
            boundCode == sessionCode,
            "Opening a mirrored terminal must bind the guest's workspace to the joined session."
        )
        #expect(
            CollaborationTerminalShareAction.primaryAction(
                role: .notShared,
                workspaceHasSession: boundCode != nil
            ) == .shareInWorkspaceSession,
            "A guest's own unshared terminal must share into the joined session instead of prompting to create a new one."
        )
    }
}
