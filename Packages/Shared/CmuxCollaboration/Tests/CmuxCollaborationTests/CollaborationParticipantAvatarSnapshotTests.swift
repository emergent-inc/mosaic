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
            color: "#7A5CFF",
            imageURL: "https://img.example/dorsa.png"
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
        #expect(snapshot.imageURL == "https://img.example/dorsa.png")
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
            colorHex: "#34C759",
            imageURL: "https://img.example/grace.png"
        )

        #expect(snapshot.id == "remote-peer")
        #expect(snapshot.displayName == "Grace Hopper")
        #expect(snapshot.initials == "GH")
        #expect(snapshot.avatarSeed == "Grace Hopper")
        #expect(snapshot.colorHex == "#34C759")
        #expect(snapshot.imageURL == "https://img.example/grace.png")
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

    @Test
    func localParticipantHasNilImageURLWhenIdentityHasNone() {
        // A signed-out or pre-imageURL identity yields no profile image, so the
        // avatar view falls back to initials rather than showing a broken image.
        let identity = CollaborationPeerIdentity(
            peerID: "local-peer",
            displayName: "Dorsa Rohani",
            color: "#7A5CFF"
        )

        let snapshot = CollaborationParticipantAvatarSnapshot.local(
            identity: identity,
            avatarSeed: "dorsa_rohani"
        )

        #expect(snapshot.imageURL == nil)
    }

    @Test
    func remoteParticipantDefaultsToNilImageURL() {
        let snapshot = CollaborationParticipantAvatarSnapshot.remote(
            peerID: "remote-peer",
            displayName: "Grace Hopper",
            colorHex: "#34C759"
        )

        #expect(snapshot.imageURL == nil)
    }

    @Test
    func explicitInitializerPreservesImageURL() {
        let snapshot = CollaborationParticipantAvatarSnapshot(
            peerID: "p",
            displayName: "Dorsa",
            initials: "D",
            avatarSeed: "dorsa",
            colorHex: "#7A5CFF",
            imageURL: "https://img.example/dorsa.png"
        )

        #expect(snapshot.imageURL == "https://img.example/dorsa.png")
    }
}
