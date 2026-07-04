import Testing
@testable import CmuxCollaboration

@Suite struct CollaborationTerminalSessionPillModelTests {
    @Test func noSessionShowsStartCallToAction() {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 0
        )
        #expect(!model.hasSession)
        #expect(!model.showsParticipantCount)
        #expect(model.otherParticipantCount == 0)
    }

    @Test func noSessionIgnoresStaleParticipantCount() {
        // Participant snapshots can outlive a torn-down session briefly; the
        // pill must not surface a count without a session.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 3
        )
        #expect(!model.showsParticipantCount)
        #expect(model.otherParticipantCount == 0)
    }

    @Test func freshSessionWithOnlyLocalParticipantShowsZero() {
        // The local user is always a participant, so a session no one else
        // has joined reads "0 other people".
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: 1
        )
        #expect(model.hasSession)
        #expect(model.showsParticipantCount)
        #expect(model.otherParticipantCount == 0)
    }

    @Test(arguments: [
        (participantCount: 2, expected: 1),
        (participantCount: 3, expected: 2),
        (participantCount: 6, expected: 5),
    ])
    func sessionCountExcludesLocalUser(participantCount: Int, expected: Int) {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: participantCount
        )
        #expect(model.showsParticipantCount)
        #expect(model.otherParticipantCount == expected)
    }

    @Test func sessionWithNoSnapshotsClampsToZero() {
        // A session whose snapshots have not populated yet (count 0) must not
        // underflow to -1.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: 0
        )
        #expect(model.otherParticipantCount == 0)
    }

    @Test func defaultsToNoIncomingBadge() {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 0
        )
        #expect(model.incomingInviteCount == 0)
        #expect(!model.showsIncomingBadge)
    }

    @Test func incomingInvitesShowBadgeWithoutASession() {
        // The badge must be visible even before a session exists so a teammate's
        // invite surfaces without opening the popover.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 0,
            incomingInviteCount: 2
        )
        #expect(!model.hasSession)
        #expect(model.incomingInviteCount == 2)
        #expect(model.showsIncomingBadge)
    }

    @Test func incomingInvitesCoexistWithParticipantCount() {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: 3,
            incomingInviteCount: 1
        )
        #expect(model.showsParticipantCount)
        #expect(model.otherParticipantCount == 2)
        #expect(model.showsIncomingBadge)
    }

    @Test func negativeIncomingCountClampsToZero() {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 0,
            incomingInviteCount: -3
        )
        #expect(model.incomingInviteCount == 0)
        #expect(!model.showsIncomingBadge)
    }
}
