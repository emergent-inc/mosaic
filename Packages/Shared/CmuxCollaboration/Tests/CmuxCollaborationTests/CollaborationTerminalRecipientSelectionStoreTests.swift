import CmuxCollaboration
import Foundation
import Testing

@Suite(.serialized)
struct CollaborationTerminalRecipientSelectionStoreTests {
    @Test
    func newParticipantsDefaultToSelected() throws {
        let store = try makeStore()

        store.record(
            selectedParticipantIDs: ["participant-a"],
            knownParticipantIDs: ["participant-a", "participant-b"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )

        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "participant-b", "participant-c"]
        ) == ["participant-a", "participant-c"])
    }

    @Test
    func selectionsPersistAcrossStoreInstances() throws {
        let suite = "cmux-collaboration-terminal-recipient-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        CollaborationTerminalRecipientSelectionStore(
            defaults: defaults,
            selectionsKey: "terminal-recipient-selections",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        ).record(
            selectedParticipantIDs: ["participant-a"],
            knownParticipantIDs: ["participant-a", "participant-b"],
            sessionCode: "8abc",
            terminalKey: "terminal-1"
        )

        let restored = CollaborationTerminalRecipientSelectionStore(
            defaults: defaults,
            selectionsKey: "terminal-recipient-selections",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(restored.selectedParticipantIDs(
            sessionCode: "8ABC",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "participant-b"]
        ) == ["participant-a"])
    }

    @Test
    func malformedPersistedPayloadIsTreatedAsEmpty() throws {
        let suite = "cmux-collaboration-terminal-recipient-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "terminal-recipient-selections")
        let store = CollaborationTerminalRecipientSelectionStore(
            defaults: defaults,
            selectionsKey: "terminal-recipient-selections",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(store.selectionsBySessionAndTerminal().isEmpty)
        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a"]
        ) == ["participant-a"])
    }

    private func makeStore() throws -> CollaborationTerminalRecipientSelectionStore {
        let suite = "cmux-collaboration-terminal-recipient-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CollaborationTerminalRecipientSelectionStore(
            defaults: defaults,
            selectionsKey: "terminal-recipient-selections",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )
    }
}
