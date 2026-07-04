import CmuxCollaboration
import Foundation
import Testing

@Suite
struct CollaborationPeerIdentityTests {
    @Test
    func ephemeralIdentitiesAreDistinctForSeparateLocalPeers() throws {
        let firstUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let first = CollaborationPeerIdentity.ephemeral(
            displayName: "Dorsa",
            colorPalette: ["#111111"],
            idProvider: { firstUUID }
        )
        let second = CollaborationPeerIdentity.ephemeral(
            displayName: "Dorsa",
            colorPalette: ["#111111"],
            idProvider: { secondUUID }
        )

        #expect(first.peerID != second.peerID)
        #expect(first.participantID == first.peerID)
        #expect(first.displayName == second.displayName)
        #expect(first.color == "#111111")
        #expect(second.color == "#111111")
    }

    @Test
    func persistedParticipantKeepsStableParticipantIDAcrossPeerIDs() throws {
        let suite = "cmux-collaboration-peer-identity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstPeerUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let secondPeerUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let participantUUID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))

        let first = CollaborationPeerIdentity.persistedParticipant(
            displayName: "Dorsa",
            defaults: defaults,
            participantIDKey: "participant-id",
            colorPalette: ["#111111"],
            peerIDProvider: { firstPeerUUID },
            participantIDProvider: { participantUUID }
        )
        let second = CollaborationPeerIdentity.persistedParticipant(
            displayName: "Dorsa",
            defaults: defaults,
            participantIDKey: "participant-id",
            colorPalette: ["#111111"],
            peerIDProvider: { secondPeerUUID },
            participantIDProvider: { UUID() }
        )

        #expect(first.peerID != second.peerID)
        #expect(first.participantID == participantUUID.uuidString)
        #expect(second.participantID == participantUUID.uuidString)
    }

    @Test
    func emptyPaletteFallsBackToDefaultColor() throws {
        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        let identity = CollaborationPeerIdentity.ephemeral(
            displayName: "Dorsa",
            colorPalette: [],
            idProvider: { uuid }
        )

        #expect(CollaborationPeerIdentity.defaultColorPalette.contains(identity.color))
    }

    @Test
    func authenticatedParticipantUsesClerkUserIDAsStableParticipantID() {
        let identity = CollaborationPeerIdentity.authenticatedParticipant(
            peerID: "peer-live-session-1",
            userID: "user_2abc",
            displayName: "Dorsa",
            imageURL: "https://img.example/dorsa.png",
            colorPalette: ["#111111", "#222222", "#333333"]
        )
        let nextProcessIdentity = CollaborationPeerIdentity.authenticatedParticipant(
            peerID: "peer-live-session-2",
            userID: "user_2abc",
            displayName: "Dorsa",
            imageURL: "https://img.example/dorsa.png",
            colorPalette: ["#111111", "#222222", "#333333"]
        )

        #expect(identity.peerID == "peer-live-session-1")
        #expect(nextProcessIdentity.peerID == "peer-live-session-2")
        #expect(identity.participantID == "user_2abc")
        #expect(nextProcessIdentity.participantID == "user_2abc")
        #expect(identity.color == nextProcessIdentity.color)
        #expect(identity.displayName == "Dorsa")
        #expect(identity.imageURL == "https://img.example/dorsa.png")
    }

    @Test
    func authenticatedParticipantDefaultsToNilImageURL() {
        let identity = CollaborationPeerIdentity.authenticatedParticipant(
            peerID: "peer-live-session-1",
            userID: "user_2abc",
            displayName: "Dorsa",
            colorPalette: ["#111111"]
        )

        #expect(identity.imageURL == nil)
    }
}
