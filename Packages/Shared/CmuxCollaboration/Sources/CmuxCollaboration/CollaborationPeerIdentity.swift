public import Foundation

/// Relay-visible identity metadata for one running collaboration peer.
public struct CollaborationPeerIdentity: Equatable, Sendable {
    /// The default color palette used to distinguish peers in collaboration UI.
    public static let defaultColorPalette = ["#7A5CFF", "#0A84FF", "#34C759", "#FF9F0A", "#FF375F"]
    /// The default key used to persist this device user's stable participant identity.
    public static let defaultParticipantIDKey = "collaboration.participantID"

    /// A relay-unique peer identifier for this app process.
    public let peerID: String
    /// Stable participant identifier used to remember share preferences across app restarts.
    public let participantID: String
    /// The display name shown to collaborators.
    public let displayName: String
    /// The display color assigned to this peer.
    public let color: String

    /// Creates peer identity metadata.
    /// - Parameters:
    ///   - peerID: A relay-unique peer identifier.
    ///   - participantID: Stable participant identifier used for persisted user preferences.
    ///   - displayName: The display name shown to collaborators.
    ///   - color: The display color assigned to this peer.
    public init(peerID: String, participantID: String? = nil, displayName: String, color: String) {
        self.peerID = peerID
        self.participantID = participantID ?? peerID
        self.displayName = displayName
        self.color = color
    }

    /// Creates a fresh peer identity for a single running app process.
    ///
    /// Collaboration relays key active connections by peer ID, so two local app
    /// windows that join the same session must not reuse a persisted bundle-wide
    /// identifier. Generate this once at process startup and reuse it for that
    /// process's collaboration connections.
    /// - Parameters:
    ///   - displayName: The display name shown to collaborators.
    ///   - colorPalette: The palette used to derive the peer color.
    ///   - idProvider: Supplies the process-local peer UUID.
    /// - Returns: Fresh relay identity metadata for one app process.
    public static func ephemeral(
        displayName: String,
        colorPalette: [String] = Self.defaultColorPalette,
        idProvider: @Sendable () -> UUID = { UUID() }
    ) -> CollaborationPeerIdentity {
        let peerID = idProvider().uuidString
        let palette = colorPalette.isEmpty ? Self.defaultColorPalette : colorPalette
        return CollaborationPeerIdentity(
            peerID: peerID,
            participantID: peerID,
            displayName: displayName,
            color: palette[Self.colorIndex(for: peerID, count: palette.count)]
        )
    }

    /// Creates a process-unique relay identity with a persisted participant identifier.
    ///
    /// Use this for app sessions where live socket connections must stay distinct but
    /// user preferences should survive app restarts.
    /// - Parameters:
    ///   - displayName: The display name shown to collaborators.
    ///   - defaults: The defaults domain that persists the stable participant ID.
    ///   - participantIDKey: The key used to store the stable participant ID.
    ///   - colorPalette: The palette used to derive the peer color.
    ///   - peerIDProvider: Supplies the process-local peer UUID.
    ///   - participantIDProvider: Supplies a participant UUID when one is not already persisted.
    /// - Returns: Relay identity metadata with distinct live and stable identifiers.
    public static func persistedParticipant(
        displayName: String,
        defaults: UserDefaults = .standard,
        participantIDKey: String = Self.defaultParticipantIDKey,
        colorPalette: [String] = Self.defaultColorPalette,
        peerIDProvider: @Sendable () -> UUID = { UUID() },
        participantIDProvider: @Sendable () -> UUID = { UUID() }
    ) -> CollaborationPeerIdentity {
        let peerID = peerIDProvider().uuidString
        let storedParticipantID = defaults.string(forKey: participantIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let participantID: String
        if let storedParticipantID, !storedParticipantID.isEmpty {
            participantID = storedParticipantID
        } else {
            participantID = participantIDProvider().uuidString
            defaults.set(participantID, forKey: participantIDKey)
        }
        let palette = colorPalette.isEmpty ? Self.defaultColorPalette : colorPalette
        return CollaborationPeerIdentity(
            peerID: peerID,
            participantID: participantID,
            displayName: displayName,
            color: palette[Self.colorIndex(for: participantID, count: palette.count)]
        )
    }

    private static func colorIndex(for peerID: String, count: Int) -> Int {
        let total = peerID.utf8.reduce(0) { partial, byte in
            partial + Int(byte)
        }
        return total % count
    }
}
