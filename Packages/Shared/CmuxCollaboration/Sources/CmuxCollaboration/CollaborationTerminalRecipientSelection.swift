/// Persisted recipient selection for one shared terminal in one collaboration session.
public struct CollaborationTerminalRecipientSelection: Codable, Equatable, Sendable {
    /// Normalized collaboration session code.
    public let sessionCode: String
    /// Stable terminal key within the session.
    public let terminalKey: String
    /// Stable participant identifiers known when this selection was saved.
    public let knownParticipantIDs: [String]
    /// Stable participant identifiers selected to receive the terminal.
    public let selectedParticipantIDs: [String]

    /// Creates a persisted terminal recipient selection.
    /// - Parameters:
    ///   - sessionCode: Normalized collaboration session code.
    ///   - terminalKey: Stable terminal key within the session.
    ///   - knownParticipantIDs: Stable participant identifiers known when this selection was saved.
    ///   - selectedParticipantIDs: Stable participant identifiers selected to receive the terminal.
    public init(
        sessionCode: String,
        terminalKey: String,
        knownParticipantIDs: [String] = [],
        selectedParticipantIDs: [String]
    ) {
        self.sessionCode = sessionCode
        self.terminalKey = terminalKey
        self.knownParticipantIDs = knownParticipantIDs
        self.selectedParticipantIDs = selectedParticipantIDs
    }
}
