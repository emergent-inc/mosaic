import CmuxCollaboration
import Testing

struct CollaborationTerminalRecipientPopoverModelTests {
    @Test(arguments: [
        -1,
        0,
    ])
    func emptyRecipientListsOfferInviteCodeInsteadOfShare(recipientCount: Int) {
        let model = CollaborationTerminalRecipientPopoverModel(recipientCount: recipientCount)

        #expect(model.recipientCount == 0)
        #expect(model.primaryAction == .copyInviteCode)
        #expect(model.showsInviteAction)
        #expect(!model.showsRecipientSelection)
        #expect(!model.showsShareAction)
        #expect(model.showsStopSharingAction)
    }

    @Test(arguments: [
        1,
        2,
        10,
    ])
    func populatedRecipientListsOfferSelectionAndShare(recipientCount: Int) {
        let model = CollaborationTerminalRecipientPopoverModel(recipientCount: recipientCount)

        #expect(model.recipientCount == recipientCount)
        #expect(model.primaryAction == .shareWithSelectedRecipients)
        #expect(!model.showsInviteAction)
        #expect(model.showsRecipientSelection)
        #expect(model.showsShareAction)
        #expect(model.showsStopSharingAction)
    }
}
