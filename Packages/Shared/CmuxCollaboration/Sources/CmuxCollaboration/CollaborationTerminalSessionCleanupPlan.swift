/// Selects every terminal whose tab presentation must be cleared when a session ends.
///
/// The router is the primary source of truth, but end-session cleanup must also
/// tolerate a partially-cleaned runtime where a terminal is still mapped to a
/// panel even though its router entry has already disappeared. Session-scoped
/// terminal identifiers start with the normalized session code, so mapped IDs
/// with that prefix are included as a recovery path.
public struct CollaborationTerminalSessionCleanupPlan: Equatable, Sendable {
    /// Session-scoped terminal identifiers that should have collaboration UI removed.
    public let terminalIDs: [String]

    /// Creates a cleanup plan for one normalized session code.
    /// - Parameters:
    ///   - sessionCode: The normalized session code being ended.
    ///   - terminalSessionRouter: The current terminal-to-session routing table.
    ///   - hostedTerminalIDs: Locally hosted terminal identifiers still mapped to panels.
    ///   - mirroredTerminalIDs: Remote mirrored terminal identifiers still mapped to panels.
    public init(
        sessionCode: String,
        terminalSessionRouter: CollaborationTerminalSessionRouter,
        hostedTerminalIDs: [String],
        mirroredTerminalIDs: [String]
    ) {
        let trimmedSessionCode = sessionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionCode.isEmpty else {
            terminalIDs = []
            return
        }
        let mappedIDs = Set(hostedTerminalIDs)
            .union(mirroredTerminalIDs)
            .filter { terminalID in
                terminalSessionRouter.sessionCode(forTerminalID: terminalID) == trimmedSessionCode
                    || terminalID.hasPrefix("\(trimmedSessionCode):")
            }
        terminalIDs = Array(Set(terminalSessionRouter.terminalIDs(inSession: trimmedSessionCode)).union(mappedIDs)).sorted()
    }
}
