import Testing
@testable import MosaicCollaboration

@Suite struct CollaborationTerminalSessionPillModelTests {
    @Test func noSessionShowsStartCallToAction() {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 0
        )
        #expect(!model.hasSession)
        #expect(!model.showsParticipantCount)
        #expect(model.totalParticipantCount == 0)
    }

    @Test func noSessionIgnoresStaleParticipantCount() {
        // Participant snapshots can outlive a torn-down session briefly; the
        // pill must not surface a count without a session.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: nil,
            participantCount: 3
        )
        #expect(!model.showsParticipantCount)
        #expect(model.totalParticipantCount == 0)
    }

    @Test func freshSessionWithOnlyLocalParticipantShowsOne() {
        // The session pill shows total people, including the local user.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: 1
        )
        #expect(model.hasSession)
        #expect(model.showsParticipantCount)
        #expect(model.totalParticipantCount == 1)
    }

    @Test(arguments: [
        (participantCount: 2, expected: 2),
        (participantCount: 3, expected: 3),
        (participantCount: 6, expected: 6),
    ])
    func sessionCountIncludesLocalUser(participantCount: Int, expected: Int) {
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: participantCount
        )
        #expect(model.showsParticipantCount)
        #expect(model.totalParticipantCount == expected)
    }

    @Test func sessionWithNoSnapshotsClampsToZero() {
        // A session whose snapshots have not populated yet (count 0) must not
        // underflow to -1.
        let model = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: "ABC123",
            participantCount: 0
        )
        #expect(model.totalParticipantCount == 0)
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
        #expect(model.totalParticipantCount == 3)
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
