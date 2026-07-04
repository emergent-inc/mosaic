import CmuxCollaboration
import Testing

/// Verifies the groupchat-style avatar stack math used by sidebar session rows:
/// every connected participant is represented, with the row collapsing extras
/// into a trailing "+N" overflow bubble once it would overflow.
struct CollaborationAvatarStackLayoutTests {
    private let cap = 4

    @Test
    func noParticipantsRendersNothing() {
        let layout = CollaborationAvatarStackLayout(participantCount: 0, maxVisibleAvatars: cap)
        #expect(layout.visibleAvatarCount == 0)
        #expect(layout.overflowCount == 0)
        #expect(layout.showsOverflowBubble == false)
        #expect(layout.slotCount == 0)
    }

    @Test(arguments: [1, 2, 3, 4])
    func everyoneShownWhenTheyFit(count: Int) {
        let layout = CollaborationAvatarStackLayout(participantCount: count, maxVisibleAvatars: cap)
        #expect(layout.visibleAvatarCount == count)
        #expect(layout.overflowCount == 0)
        #expect(layout.showsOverflowBubble == false)
        #expect(layout.slotCount == count)
    }

    @Test
    func overflowReservesTheLastSlotForTheBubble() {
        let layout = CollaborationAvatarStackLayout(participantCount: 5, maxVisibleAvatars: cap)
        // 3 avatars + a "+2" bubble == 4 drawn circles, still representing all 5.
        #expect(layout.visibleAvatarCount == 3)
        #expect(layout.overflowCount == 2)
        #expect(layout.showsOverflowBubble == true)
        #expect(layout.slotCount == cap)
    }

    @Test(arguments: [
        (count: 5, overflow: 2),
        (count: 8, overflow: 5),
        (count: 42, overflow: 39),
    ])
    func overflowCountAlwaysAccountsForEveryParticipant(count: Int, overflow: Int) {
        let layout = CollaborationAvatarStackLayout(participantCount: count, maxVisibleAvatars: cap)
        #expect(layout.visibleAvatarCount == cap - 1)
        #expect(layout.overflowCount == overflow)
        // No connected person is ever silently dropped.
        #expect(layout.visibleAvatarCount + layout.overflowCount == count)
        // The drawn row never exceeds the cap.
        #expect(layout.slotCount == cap)
    }

    @Test
    func degenerateCapIsClampedToAtLeastOne() {
        let layout = CollaborationAvatarStackLayout(participantCount: 5, maxVisibleAvatars: 0)
        #expect(layout.visibleAvatarCount == 0)
        #expect(layout.overflowCount == 5)
        #expect(layout.slotCount == 1)
    }

    @Test
    func negativeParticipantCountIsTreatedAsEmpty() {
        let layout = CollaborationAvatarStackLayout(participantCount: -3, maxVisibleAvatars: cap)
        #expect(layout.visibleAvatarCount == 0)
        #expect(layout.overflowCount == 0)
        #expect(layout.slotCount == 0)
    }
}
