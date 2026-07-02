import CmuxCollaboration
import Testing

struct CollaborationParticipantAvatarSnapshotTests {
    @Test(arguments: [
        (value: "Ada Lovelace", initials: "AL"),
        (value: " dorsa_rohani ", initials: "DR"),
        (value: "cmux-session", initials: "CS"),
        (value: "single", initials: "S"),
        (value: "", initials: "?"),
        (value: "   ", initials: "?"),
    ])
    func initialsUseAtMostTwoWordBoundaries(value: String, initials: String) {
        #expect(CollaborationParticipantAvatarSnapshot.initials(for: value) == initials)
    }

    @Test
    func localParticipantUsesWhoamiSeedForInitialsAndAvatarSeed() {
        let identity = CollaborationPeerIdentity(
            peerID: "local-peer",
            displayName: "Dorsa Rohani",
            color: "#7A5CFF"
        )

        let snapshot = CollaborationParticipantAvatarSnapshot.local(
            identity: identity,
            avatarSeed: "dorsa_rohani"
        )

        #expect(snapshot.id == "local-peer")
        #expect(snapshot.peerID == "local-peer")
        #expect(snapshot.displayName == "Dorsa Rohani")
        #expect(snapshot.initials == "DR")
        #expect(snapshot.avatarSeed == "dorsa_rohani")
        #expect(snapshot.colorHex == "#7A5CFF")
    }

    @Test
    func localParticipantFallsBackToDisplayNameWhenWhoamiSeedIsBlank() {
        let identity = CollaborationPeerIdentity(
            peerID: "local-peer",
            displayName: "Ada Lovelace",
            color: "#0A84FF"
        )

        let snapshot = CollaborationParticipantAvatarSnapshot.local(
            identity: identity,
            avatarSeed: "   "
        )

        #expect(snapshot.initials == "AL")
        #expect(snapshot.avatarSeed == "Ada Lovelace")
    }

    @Test
    func remoteParticipantUsesDisplayNameAsSeedAndInitials() {
        let snapshot = CollaborationParticipantAvatarSnapshot.remote(
            peerID: "remote-peer",
            displayName: "Grace Hopper",
            colorHex: "#34C759"
        )

        #expect(snapshot.id == "remote-peer")
        #expect(snapshot.displayName == "Grace Hopper")
        #expect(snapshot.initials == "GH")
        #expect(snapshot.avatarSeed == "Grace Hopper")
        #expect(snapshot.colorHex == "#34C759")
    }

    @Test
    func remoteParticipantFallsBackToPeerIDSeedWhenDisplayNameIsBlank() {
        let snapshot = CollaborationParticipantAvatarSnapshot.remote(
            peerID: "remote-peer",
            displayName: " ",
            colorHex: "#FF9F0A"
        )

        #expect(snapshot.initials == "?")
        #expect(snapshot.avatarSeed == "remote-peer")
    }
}
