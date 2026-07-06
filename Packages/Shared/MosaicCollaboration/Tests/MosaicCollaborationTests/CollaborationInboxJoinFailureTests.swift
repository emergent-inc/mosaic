import MosaicCollaboration
import Testing

@Suite struct CollaborationInboxJoinFailureTests {
    @Test func goneStatusMeansInviteShouldBePruned() {
        #expect(CollaborationInboxJoinFailure.indicatesInviteGone(status: 410, code: nil))
        #expect(CollaborationInboxJoinFailure.indicatesInviteGone(status: 403, code: nil))
    }

    @Test func knownErrorCodesMeanInviteShouldBePruned() {
        #expect(CollaborationInboxJoinFailure.indicatesInviteGone(status: 400, code: "session_ended"))
        #expect(CollaborationInboxJoinFailure.indicatesInviteGone(status: 400, code: "not_invited"))
        #expect(CollaborationInboxJoinFailure.indicatesInviteGone(status: 400, code: "invalid_session"))
    }

    @Test func transientFailuresKeepTheInvite() {
        #expect(!CollaborationInboxJoinFailure.indicatesInviteGone(status: 500, code: nil))
        #expect(!CollaborationInboxJoinFailure.indicatesInviteGone(status: 502, code: "bad_gateway"))
        #expect(!CollaborationInboxJoinFailure.indicatesInviteGone(status: 429, code: nil))
        #expect(!CollaborationInboxJoinFailure.indicatesInviteGone(status: -1, code: nil))
    }
}
