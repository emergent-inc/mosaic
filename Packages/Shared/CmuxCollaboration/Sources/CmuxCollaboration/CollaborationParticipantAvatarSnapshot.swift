import Foundation

/// Immutable participant display data for compact collaboration avatar UI.
public struct CollaborationParticipantAvatarSnapshot: Equatable, Identifiable, Sendable {
    /// Relay-visible peer identifier.
    public let peerID: String
    /// Display name shown for the participant.
    public let displayName: String
    /// Initials used by generated avatar providers and local fallbacks.
    public let initials: String
    /// Stable seed used for generated avatars.
    public let avatarSeed: String
    /// Hex color used for local avatar fallback rendering.
    public let colorHex: String

    /// Stable identity for SwiftUI lists.
    public var id: String { peerID }

    /// Creates participant display data.
    /// - Parameters:
    ///   - peerID: Relay-visible peer identifier.
    ///   - displayName: Display name shown for the participant.
    ///   - initials: Initials used by generated avatar providers and local fallbacks.
    ///   - avatarSeed: Stable seed used for generated avatars.
    ///   - colorHex: Hex color used for local avatar fallback rendering.
    public init(
        peerID: String,
        displayName: String,
        initials: String,
        avatarSeed: String,
        colorHex: String
    ) {
        self.peerID = peerID
        self.displayName = displayName
        self.initials = initials
        self.avatarSeed = avatarSeed
        self.colorHex = colorHex
    }

    /// Creates display data for the local participant.
    /// - Parameters:
    ///   - identity: The local relay identity.
    ///   - avatarSeed: The local seed, usually the current `whoami` value.
    /// - Returns: Display data for the local participant.
    public static func local(
        identity: CollaborationPeerIdentity,
        avatarSeed: String
    ) -> CollaborationParticipantAvatarSnapshot {
        let seed = avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSeed = seed.isEmpty ? identity.displayName : seed
        return CollaborationParticipantAvatarSnapshot(
            peerID: identity.peerID,
            displayName: identity.displayName,
            initials: initials(for: resolvedSeed),
            avatarSeed: resolvedSeed,
            colorHex: identity.color
        )
    }

    /// Creates display data for a remote participant.
    /// - Parameters:
    ///   - peerID: Relay-visible peer identifier.
    ///   - displayName: Display name reported by the remote peer.
    ///   - colorHex: Hex color reported by the remote peer.
    /// - Returns: Display data for the remote participant.
    public static func remote(
        peerID: String,
        displayName: String,
        colorHex: String
    ) -> CollaborationParticipantAvatarSnapshot {
        let seed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSeed = seed.isEmpty ? peerID : seed
        return CollaborationParticipantAvatarSnapshot(
            peerID: peerID,
            displayName: displayName,
            initials: initials(for: displayName),
            avatarSeed: resolvedSeed,
            colorHex: colorHex
        )
    }

    /// Returns at most two uppercase initials from a display or seed value.
    /// - Parameter value: A display name or avatar seed.
    /// - Returns: One or two initials, or `?` when no initial can be derived.
    public static func initials(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." })
        let initials = words
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        if !initials.isEmpty {
            return initials
        }
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }
}
