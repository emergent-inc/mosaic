import Testing
@testable import cmux

/// Behavior of the terminal-header share-button label: it must read
/// "Sharing with …" (never the old "Shared to …") and carry the live
/// recipient count.
@Suite struct CollaborationSharingLabelTests {
    @Test func zeroRecipientsReadsSharingWithNoOne() {
        #expect(CollaborationStrings.sharingWithRecipientCount(0) == "Sharing with no one")
    }

    @Test func negativeRecipientCountClampsToNoOne() {
        #expect(CollaborationStrings.sharingWithRecipientCount(-1) == "Sharing with no one")
    }

    @Test(arguments: [1, 2, 5, 12])
    func positiveRecipientCountReadsSharingWithCount(count: Int) {
        #expect(CollaborationStrings.sharingWithRecipientCount(count) == "Sharing with \(count)")
    }
}
