import MosaicCollaboration
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
        let suite = "mosaic-collaboration-terminal-recipient-store-\(UUID().uuidString)"
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
        let suite = "mosaic-collaboration-terminal-recipient-store-\(UUID().uuidString)"
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

    @Test
    func hasSelectionReflectsRecordedSelections() throws {
        let store = try makeStore()

        #expect(!store.hasSelection(sessionCode: "5z-nh", terminalKey: "terminal-1"))

        store.record(
            selectedParticipantIDs: [],
            knownParticipantIDs: ["participant-a"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )

        #expect(store.hasSelection(sessionCode: "5ZNH", terminalKey: "terminal-1"))
        #expect(!store.hasSelection(sessionCode: "5ZNH", terminalKey: "terminal-2"))
        #expect(!store.hasSelection(sessionCode: "", terminalKey: "terminal-1"))
    }

    @Test
    func emptyRecordedSelectionResolvesToNoRecipients() throws {
        let store = try makeStore()

        store.record(
            selectedParticipantIDs: [],
            knownParticipantIDs: ["participant-a", "participant-b"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )

        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "participant-b"]
        ).isEmpty)
    }

    @Test
    func recordKnownParticipantsKeepsLateJoinerUnselected() throws {
        let store = try makeStore()

        store.record(
            selectedParticipantIDs: ["participant-a"],
            knownParticipantIDs: ["participant-a", "participant-b"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )
        store.recordKnownParticipants(
            ["participant-c"],
            sessionCode: "5ZNH",
            terminalKey: "terminal-1"
        )

        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "participant-b", "participant-c"]
        ) == ["participant-a"])
    }

    @Test
    func recordKnownParticipantsDoesNothingWithoutSelection() throws {
        let store = try makeStore()

        store.recordKnownParticipants(
            ["participant-a"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )

        #expect(!store.hasSelection(sessionCode: "5ZNH", terminalKey: "terminal-1"))
        // Without a recorded selection, new peers keep the default of being included.
        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a"]
        ) == ["participant-a"])
    }

    @Test
    func recordKnownParticipantsPreservesExistingSelection() throws {
        let store = try makeStore()

        store.record(
            selectedParticipantIDs: ["participant-a"],
            knownParticipantIDs: ["participant-a"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )
        // Recording an already-selected participant as known must not unselect them.
        store.recordKnownParticipants(
            ["participant-a", "participant-b"],
            sessionCode: "5ZNH",
            terminalKey: "terminal-1"
        )

        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "participant-b"]
        ) == ["participant-a"])
    }

    @Test
    func recordSelectedParticipantsAddsInviteeAsRecipient() throws {
        let store = try makeStore()

        store.record(
            selectedParticipantIDs: [],
            knownParticipantIDs: ["participant-a"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )
        store.recordSelectedParticipants(
            ["invitee-user-id"],
            sessionCode: "5ZNH",
            terminalKey: "terminal-1"
        )

        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "invitee-user-id"]
        ) == ["invitee-user-id"])
        // The invitee must survive a later known-only merge (their join event).
        store.recordKnownParticipants(
            ["invitee-user-id"],
            sessionCode: "5ZNH",
            terminalKey: "terminal-1"
        )
        #expect(store.selectedParticipantIDs(
            sessionCode: "5ZNH",
            terminalKey: "terminal-1",
            currentParticipantIDs: ["participant-a", "invitee-user-id"]
        ) == ["invitee-user-id"])
    }

    @Test
    func recordSelectedParticipantsDoesNothingWithoutSelection() throws {
        let store = try makeStore()

        store.recordSelectedParticipants(
            ["invitee-user-id"],
            sessionCode: "5z-nh",
            terminalKey: "terminal-1"
        )

        #expect(!store.hasSelection(sessionCode: "5ZNH", terminalKey: "terminal-1"))
    }

    private func makeStore() throws -> CollaborationTerminalRecipientSelectionStore {
        let suite = "mosaic-collaboration-terminal-recipient-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CollaborationTerminalRecipientSelectionStore(
            defaults: defaults,
            selectionsKey: "terminal-recipient-selections",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )
    }
}
