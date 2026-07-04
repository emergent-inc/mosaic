public import Foundation

/// What to render for a single collaboration participant avatar.
///
/// The precedence is intentionally two-tier: the participant's real account
/// profile picture when one is available, otherwise initials as an *absolute
/// backup*. There is deliberately no generated-initials middle tier (e.g. a
/// DiceBear "initials" image) — initials should only ever appear when no real
/// account picture can be shown.
public enum CollaborationAvatarContent: Equatable, Sendable {
    /// Render the participant's real account profile picture at this URL.
    case remoteImage(URL)
    /// No usable account picture; render initials as the absolute backup.
    case initialsFallback
}

extension CollaborationParticipantAvatarSnapshot {
    /// The account profile-image URL to display, if the stored value is a
    /// usable `http`/`https` URL.
    ///
    /// Empty/whitespace values and non-web schemes (`file:`, `data:`,
    /// `javascript:`, …) resolve to `nil` so they never reach an image loader.
    public var resolvedProfileImageURL: URL? {
        guard let raw = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        switch url.scheme?.lowercased() {
        case "http", "https":
            return url
        default:
            return nil
        }
    }

    /// The avatar content to render for this participant: the real account
    /// picture when available, otherwise the initials backup.
    public var avatarContent: CollaborationAvatarContent {
        if let url = resolvedProfileImageURL {
            return .remoteImage(url)
        }
        return .initialsFallback
    }
}
