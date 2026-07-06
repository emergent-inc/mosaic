public import Foundation

/// Describes one terminal surface shared in a collaboration session.
public struct SharedTerminalDescriptor: Codable, Equatable, Hashable, Sendable {
    /// The workspace that owns the terminal surface on the sharing peer.
    public let workspaceID: UUID
    /// The stable terminal surface identifier.
    public let surfaceID: UUID
    /// The user-visible terminal title.
    public let title: String

    /// Creates a shared terminal descriptor.
    /// - Parameters:
    ///   - workspaceID: The workspace that owns the terminal surface on the sharing peer.
    ///   - surfaceID: The stable terminal surface identifier.
    ///   - title: The user-visible terminal title.
    public init(workspaceID: UUID, surfaceID: UUID, title: String) {
        self.workspaceID = workspaceID
        self.surfaceID = surfaceID
        self.title = title
    }

    /// The stable collaboration terminal identifier for a session.
    /// - Parameter sessionID: The current collaboration session identifier.
    /// - Returns: A terminal identifier scoped to the session.
    public func terminalID(sessionID: String) -> String {
        "\(sessionID):terminal:\(workspaceID.uuidString):\(surfaceID.uuidString)"
    }

    /// Extracts the host's workspace and surface identifiers from a collaboration
    /// terminal identifier produced by ``terminalID(sessionID:)``.
    ///
    /// The identifier layout is `"<sessionID>:terminal:<workspaceID>:<surfaceID>"`.
    /// The trailing two `:`-separated components are the workspace and surface
    /// UUIDs on the *sharing* (host) peer, which lets a viewer resolve the real
    /// host surface behind a mirrored terminal (whose local pane UUID differs).
    /// - Parameter terminalID: A session-scoped collaboration terminal identifier.
    /// - Returns: The host workspace and surface identifiers, or `nil` when the
    ///   identifier is not in the expected format.
    public static func parse(terminalID: String) -> (workspaceID: UUID, surfaceID: UUID)? {
        guard let markerRange = terminalID.range(of: ":terminal:") else { return nil }
        let tail = terminalID[markerRange.upperBound...]
        let components = tail.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let workspaceID = UUID(uuidString: String(components[0])),
              let surfaceID = UUID(uuidString: String(components[1])) else {
            return nil
        }
        return (workspaceID, surfaceID)
    }
}
