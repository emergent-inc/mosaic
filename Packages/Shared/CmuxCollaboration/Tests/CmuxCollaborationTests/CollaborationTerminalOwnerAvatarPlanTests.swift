import CmuxCollaboration
import Foundation
import Testing

struct CollaborationTerminalOwnerAvatarPlanTests {
    @Test
    func profileImageURLCreatesInitialFallbackAndAsyncRequestKey() throws {
        let snapshot = Self.snapshot(imageURL: " https://img.example/ada.png?size=64 ")

        let plan = CollaborationTerminalOwnerAvatarPlan(
            ownerSnapshot: snapshot,
            title: "Ada's terminal"
        )

        #expect(plan.title == "Ada's terminal")
        #expect(plan.fallbackSnapshot == snapshot)
        #expect(plan.profileImageURL == URL(string: "https://img.example/ada.png?size=64"))
        #expect(plan.requestKey == "peer-ada|https://img.example/ada.png?size=64")
    }

    @Test(arguments: [
        nil,
        "",
        "   ",
        "file:///Users/ada/avatar.png",
        "data:image/png;base64,AAAA",
        "javascript:alert(1)",
        "ftp://img.example/ada.png",
    ] as [String?])
    func unusableProfileImageURLKeepsOnlyInitialsFallback(imageURL: String?) {
        let snapshot = Self.snapshot(imageURL: imageURL)

        let plan = CollaborationTerminalOwnerAvatarPlan(
            ownerSnapshot: snapshot,
            title: "Ada's terminal"
        )

        #expect(plan.fallbackSnapshot == snapshot)
        #expect(plan.profileImageURL == nil)
        #expect(plan.requestKey == nil)
    }

    @Test
    func nilOwnerClearsTitleFallbackAndRemoteRequest() {
        let plan = CollaborationTerminalOwnerAvatarPlan(
            ownerSnapshot: nil,
            title: nil
        )

        #expect(plan.title == nil)
        #expect(plan.fallbackSnapshot == nil)
        #expect(plan.profileImageURL == nil)
        #expect(plan.requestKey == nil)
    }

    @Test
    func staleAsyncProfileImageResultsAreRejected() {
        #expect(CollaborationTerminalOwnerAvatarPlan.shouldApplyProfileImage(
            requestKey: "peer-ada|https://img.example/ada.png",
            currentRequestKey: "peer-ada|https://img.example/ada.png"
        ))
        #expect(!CollaborationTerminalOwnerAvatarPlan.shouldApplyProfileImage(
            requestKey: "peer-ada|https://img.example/old.png",
            currentRequestKey: "peer-ada|https://img.example/new.png"
        ))
        #expect(!CollaborationTerminalOwnerAvatarPlan.shouldApplyProfileImage(
            requestKey: "peer-ada|https://img.example/ada.png",
            currentRequestKey: nil
        ))
    }

    @Test
    func requestKeyChangesWhenOwnerChangesEvenForSameImageURL() {
        let first = CollaborationTerminalOwnerAvatarPlan(
            ownerSnapshot: Self.snapshot(peerID: "peer-1", imageURL: "https://img.example/shared.png"),
            title: "First"
        )
        let second = CollaborationTerminalOwnerAvatarPlan(
            ownerSnapshot: Self.snapshot(peerID: "peer-2", imageURL: "https://img.example/shared.png"),
            title: "Second"
        )

        #expect(first.requestKey == "peer-1|https://img.example/shared.png")
        #expect(second.requestKey == "peer-2|https://img.example/shared.png")
        #expect(first.requestKey != second.requestKey)
    }

    private static func snapshot(
        peerID: String = "peer-ada",
        imageURL: String?
    ) -> CollaborationParticipantAvatarSnapshot {
        CollaborationParticipantAvatarSnapshot(
            peerID: peerID,
            displayName: "Ada Lovelace",
            initials: "AL",
            avatarSeed: "ada_lovelace",
            colorHex: "#7A5CFF",
            imageURL: imageURL
        )
    }
}
