public import Foundation

/// Stores selected recipients for shared terminals.
public struct CollaborationTerminalRecipientSelectionStore {
    /// The default key used for terminal recipient selections.
    public static let defaultSelectionsKey = "collaboration.terminalRecipientSelections"

    private let defaults: UserDefaults
    private let selectionsKey: String
    private let inviteCodeStore: CollaborationInviteCodeStore

    /// Creates a terminal recipient selection store.
    /// - Parameters:
    ///   - defaults: The defaults domain that persists terminal recipient selections.
    ///   - selectionsKey: The key used for terminal recipient selections.
    ///   - inviteCodeStore: The invite-code normalizer used before persisting session codes.
    public init(
        defaults: UserDefaults = .standard,
        selectionsKey: String = Self.defaultSelectionsKey,
        inviteCodeStore: CollaborationInviteCodeStore = CollaborationInviteCodeStore()
    ) {
        self.defaults = defaults
        self.selectionsKey = selectionsKey
        self.inviteCodeStore = inviteCodeStore
    }

    /// Returns all valid recipient selections keyed by session code and terminal key.
    public func selectionsBySessionAndTerminal() -> [String: [String: CollaborationTerminalRecipientSelection]] {
        guard let data = defaults.data(forKey: selectionsKey) else { return [:] }
        guard let stored = try? JSONDecoder().decode([CollaborationTerminalRecipientSelection].self, from: data) else {
            return [:]
        }
        return stored.reduce(into: [:]) { result, selection in
            let sessionCode = inviteCodeStore.normalizedSessionCode(from: selection.sessionCode)
            let terminalKey = selection.terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionCode.isEmpty, !terminalKey.isEmpty else { return }
            let knownIDs = Self.normalizedParticipantIDs(selection.knownParticipantIDs)
            let participantIDs = Self.normalizedParticipantIDs(selection.selectedParticipantIDs)
            result[sessionCode, default: [:]][terminalKey] = CollaborationTerminalRecipientSelection(
                sessionCode: sessionCode,
                terminalKey: terminalKey,
                knownParticipantIDs: knownIDs,
                selectedParticipantIDs: participantIDs
            )
        }
    }

    /// Returns the selected participants for a terminal, defaulting unseen peers to selected.
    /// - Parameters:
    ///   - sessionCode: The collaboration session code.
    ///   - terminalKey: The stable terminal key.
    ///   - currentParticipantIDs: Participant IDs currently available in the session.
    /// - Returns: The selected participant IDs.
    public func selectedParticipantIDs(
        sessionCode: String,
        terminalKey: String,
        currentParticipantIDs: [String]
    ) -> Set<String> {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        let normalizedKey = terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentIDs = Self.normalizedParticipantIDs(currentParticipantIDs)
        guard !normalizedCode.isEmpty, !normalizedKey.isEmpty else {
            return Set(currentIDs)
        }
        guard let stored = selectionsBySessionAndTerminal()[normalizedCode]?[normalizedKey] else {
            return Set(currentIDs)
        }
        let storedIDs = Set(stored.selectedParticipantIDs)
        let knownIDs = Set(stored.knownParticipantIDs)
        return Set(currentIDs.filter { storedIDs.contains($0) || !knownIDs.contains($0) })
    }

    /// Returns whether an explicit recipient selection has been recorded for a terminal.
    /// - Parameters:
    ///   - sessionCode: The collaboration session code.
    ///   - terminalKey: The stable terminal key.
    /// - Returns: True when a selection was previously recorded for this session and terminal.
    public func hasSelection(sessionCode: String, terminalKey: String) -> Bool {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        let normalizedKey = terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty, !normalizedKey.isEmpty else { return false }
        return selectionsBySessionAndTerminal()[normalizedCode]?[normalizedKey] != nil
    }

    /// Records additional participants as known without selecting them.
    ///
    /// Used when a peer joins a session after the host already made an explicit
    /// recipient selection: the joiner must not be auto-included, so they are
    /// recorded as known-but-unselected. Does nothing when no selection exists
    /// (terminals without a selection keep the default of including new peers).
    /// - Parameters:
    ///   - participantIDs: Participant IDs to record as known.
    ///   - sessionCode: The collaboration session code.
    ///   - terminalKey: The stable terminal key.
    public func recordKnownParticipants(
        _ participantIDs: Set<String>,
        sessionCode: String,
        terminalKey: String
    ) {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        let normalizedKey = terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty, !normalizedKey.isEmpty else { return }
        var selections = selectionsBySessionAndTerminal()
        guard let stored = selections[normalizedCode]?[normalizedKey] else { return }
        let knownIDs = Set(stored.knownParticipantIDs).union(participantIDs)
        selections[normalizedCode, default: [:]][normalizedKey] = CollaborationTerminalRecipientSelection(
            sessionCode: normalizedCode,
            terminalKey: normalizedKey,
            knownParticipantIDs: Self.normalizedParticipantIDs(Array(knownIDs)),
            selectedParticipantIDs: stored.selectedParticipantIDs
        )
        persist(selections)
    }

    /// Records additional participants as selected recipients (and known).
    ///
    /// Used when the host explicitly invites a teammate into a session: the
    /// invitee must receive already-shared terminals when they join, even
    /// though they were not present when the selection was made. Does nothing
    /// when no selection exists (the store default already includes new peers).
    /// - Parameters:
    ///   - participantIDs: Participant IDs to record as selected.
    ///   - sessionCode: The collaboration session code.
    ///   - terminalKey: The stable terminal key.
    public func recordSelectedParticipants(
        _ participantIDs: Set<String>,
        sessionCode: String,
        terminalKey: String
    ) {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        let normalizedKey = terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty, !normalizedKey.isEmpty else { return }
        var selections = selectionsBySessionAndTerminal()
        guard let stored = selections[normalizedCode]?[normalizedKey] else { return }
        let knownIDs = Set(stored.knownParticipantIDs).union(participantIDs)
        let selectedIDs = Set(stored.selectedParticipantIDs).union(participantIDs)
        selections[normalizedCode, default: [:]][normalizedKey] = CollaborationTerminalRecipientSelection(
            sessionCode: normalizedCode,
            terminalKey: normalizedKey,
            knownParticipantIDs: Self.normalizedParticipantIDs(Array(knownIDs)),
            selectedParticipantIDs: Self.normalizedParticipantIDs(Array(selectedIDs))
        )
        persist(selections)
    }

    /// Records the selected participants for a terminal.
    /// - Parameters:
    ///   - selectedParticipantIDs: Participant IDs selected to receive this terminal.
    ///   - knownParticipantIDs: Participant IDs visible when the selection was saved.
    ///   - sessionCode: The collaboration session code.
    ///   - terminalKey: The stable terminal key.
    public func record(
        selectedParticipantIDs: Set<String>,
        knownParticipantIDs: Set<String>,
        sessionCode: String,
        terminalKey: String
    ) {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        let normalizedKey = terminalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty, !normalizedKey.isEmpty else { return }
        var selections = selectionsBySessionAndTerminal()
        selections[normalizedCode, default: [:]][normalizedKey] = CollaborationTerminalRecipientSelection(
            sessionCode: normalizedCode,
            terminalKey: normalizedKey,
            knownParticipantIDs: Self.normalizedParticipantIDs(Array(knownParticipantIDs)),
            selectedParticipantIDs: Self.normalizedParticipantIDs(Array(selectedParticipantIDs))
        )
        persist(selections)
    }

    /// Removes every terminal recipient selection.
    public func removeAll() {
        defaults.removeObject(forKey: selectionsKey)
    }

    private func persist(_ selections: [String: [String: CollaborationTerminalRecipientSelection]]) {
        let sorted = selections.values
            .flatMap(\.values)
            .sorted {
                if $0.sessionCode == $1.sessionCode {
                    return $0.terminalKey < $1.terminalKey
                }
                return $0.sessionCode < $1.sessionCode
            }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: selectionsKey)
    }

    private static func normalizedParticipantIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }.sorted()
    }

}
