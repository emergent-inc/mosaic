public import Foundation

/// Invite details used to join a relay-backed collaboration session.
public struct CollaborationInvite: Codable, Equatable, Sendable {
    /// The relay WebSocket endpoint.
    public let relayURL: URL
    /// The short user-shareable session code.
    public let sessionCode: String

    /// Creates collaboration invite details.
    /// - Parameters:
    ///   - relayURL: The relay WebSocket endpoint.
    ///   - sessionCode: The short user-shareable session code.
    public init(relayURL: URL, sessionCode: String) {
        self.relayURL = relayURL
        self.sessionCode = sessionCode
    }
}
