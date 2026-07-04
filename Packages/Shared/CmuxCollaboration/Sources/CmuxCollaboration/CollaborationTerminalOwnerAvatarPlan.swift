public import Foundation

/// Immutable presentation plan for a shared terminal owner's tab avatar.
///
/// Terminal tabs render a local initials avatar immediately, then replace it
/// with the owner's real account image after the image fetch/render pipeline
/// succeeds. This value keeps the URL normalization and stale-request keying
/// testable outside the app target.
public struct CollaborationTerminalOwnerAvatarPlan: Equatable, Sendable {
    /// The tab title to show while the terminal is shared.
    public let title: String?
    /// The owner snapshot used to render the immediate initials fallback.
    public let fallbackSnapshot: CollaborationParticipantAvatarSnapshot?
    /// The normalized remote profile image URL to fetch, if one is usable.
    public let profileImageURL: URL?
    /// The key used to reject stale async profile-image replacements.
    public let requestKey: String?

    /// Creates a terminal owner avatar presentation plan.
    /// - Parameters:
    ///   - ownerSnapshot: The current terminal owner snapshot, if any.
    ///   - title: The title derived for the owner's terminal.
    public init(ownerSnapshot: CollaborationParticipantAvatarSnapshot?, title: String?) {
        self.title = title
        self.fallbackSnapshot = ownerSnapshot
        self.profileImageURL = ownerSnapshot?.resolvedProfileImageURL
        if let ownerSnapshot, let profileImageURL {
            self.requestKey = Self.requestKey(peerID: ownerSnapshot.peerID, profileImageURL: profileImageURL)
        } else {
            self.requestKey = nil
        }
    }

    /// Returns whether an async profile image result still matches the active request.
    /// - Parameters:
    ///   - requestKey: The key captured when the image request started.
    ///   - currentRequestKey: The currently active key for the terminal.
    /// - Returns: `true` when the async result belongs to the current owner/image.
    public static func shouldApplyProfileImage(
        requestKey: String,
        currentRequestKey: String?
    ) -> Bool {
        currentRequestKey == requestKey
    }

    private static func requestKey(peerID: String, profileImageURL: URL) -> String {
        "\(peerID)|\(profileImageURL.absoluteString)"
    }
}
