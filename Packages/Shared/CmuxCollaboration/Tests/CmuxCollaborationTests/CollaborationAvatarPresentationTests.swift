import CmuxCollaboration
import Foundation
import Testing

/// Verifies the avatar precedence used by terminal tabs and sidebar session
/// rows: the participant's real account profile picture is preferred, and
/// initials are only ever an absolute backup (no generated-initials tier).
struct CollaborationAvatarPresentationTests {
    private func snapshot(imageURL: String?) -> CollaborationParticipantAvatarSnapshot {
        CollaborationParticipantAvatarSnapshot(
            peerID: "peer",
            displayName: "Ada Lovelace",
            initials: "AL",
            avatarSeed: "ada_lovelace",
            colorHex: "#7A5CFF",
            imageURL: imageURL
        )
    }

    @Test(arguments: [
        "https://lh3.googleusercontent.com/a/ada.png",
        "http://avatars.githubusercontent.com/u/1?v=4",
        "  https://img.example/ada.png  ", // surrounding whitespace is trimmed
    ])
    func realAccountPictureIsPreferred(rawURL: String) throws {
        let participant = snapshot(imageURL: rawURL)

        let resolved = try #require(participant.resolvedProfileImageURL)
        #expect(resolved == URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(participant.avatarContent == .remoteImage(resolved))
    }

    @Test(arguments: [
        nil,               // no picture on file
        "",                // empty
        "   ",             // whitespace only
        "file:///Users/ada/pic.png",   // non-web scheme
        "data:image/png;base64,AAAA",  // data URI
        "javascript:alert(1)",         // unsafe scheme
        "ftp://host/pic.png",          // unsupported scheme
    ] as [String?])
    func initialsAreTheAbsoluteBackupWhenNoRealPicture(rawURL: String?) {
        let participant = snapshot(imageURL: rawURL)

        #expect(participant.resolvedProfileImageURL == nil)
        #expect(participant.avatarContent == .initialsFallback)
    }

    @Test
    func remoteContentCarriesTheExactURL() throws {
        let participant = snapshot(imageURL: "https://img.example/ada.png?size=64")

        guard case .remoteImage(let url) = participant.avatarContent else {
            Issue.record("expected remote image content")
            return
        }
        #expect(url.absoluteString == "https://img.example/ada.png?size=64")
    }
}
