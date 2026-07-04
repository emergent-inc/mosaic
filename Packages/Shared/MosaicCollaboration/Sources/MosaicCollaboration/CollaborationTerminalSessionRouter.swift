/// Records which collaboration session owns each shared terminal.
public struct CollaborationTerminalSessionRouter: Equatable, Sendable {
    private var sessionCodesByTerminalID: [String: String]

    /// Creates an empty terminal session router.
    public init(sessionCodesByTerminalID: [String: String] = [:]) {
        self.sessionCodesByTerminalID = sessionCodesByTerminalID
    }

    /// Records that a terminal is shared through a session.
    /// - Parameters:
    ///   - terminalID: The session-scoped terminal identifier.
    ///   - sessionCode: The normalized invite code for the owning session.
    public mutating func record(terminalID: String, sessionCode: String) {
        sessionCodesByTerminalID[terminalID] = sessionCode
    }

    /// Returns the session code that owns a terminal.
    /// - Parameter terminalID: The session-scoped terminal identifier.
    /// - Returns: The normalized invite code for the owning session, if known.
    public func sessionCode(forTerminalID terminalID: String) -> String? {
        sessionCodesByTerminalID[terminalID]
    }

    /// Returns the terminals owned by a session.
    /// - Parameter sessionCode: The normalized invite code for the owning session.
    /// - Returns: The session-scoped terminal identifiers owned by the session.
    public func terminalIDs(inSession sessionCode: String) -> [String] {
        sessionCodesByTerminalID
            .filter { $0.value == sessionCode }
            .map(\.key)
            .sorted()
    }

    /// Removes ownership for a terminal.
    /// - Parameter terminalID: The session-scoped terminal identifier.
    public mutating func remove(terminalID: String) {
        sessionCodesByTerminalID.removeValue(forKey: terminalID)
    }

    /// Removes every recorded terminal ownership.
    public mutating func removeAll() {
        sessionCodesByTerminalID.removeAll()
    }
}
