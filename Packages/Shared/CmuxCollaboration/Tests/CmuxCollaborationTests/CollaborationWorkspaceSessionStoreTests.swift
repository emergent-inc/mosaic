import CmuxCollaboration
import Foundation
import Testing

@Suite(.serialized)
struct CollaborationWorkspaceSessionStoreTests {
    @Test
    func recordsNormalizedSessionCodeForWorkspace() throws {
        let store = try makeStore()
        let workspaceID = UUID()

        store.record(sessionCode: "5z-nh", forWorkspaceID: workspaceID)

        #expect(store.sessionCode(forWorkspaceID: workspaceID) == "5ZNH")
        #expect(store.bindingsByWorkspaceID()[workspaceID] == CollaborationWorkspaceSessionBinding(
            workspaceID: workspaceID,
            sessionCode: "5ZNH"
        ))
    }

    @Test
    func workspaceBindingsPersistAcrossStoreInstances() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspaceID = UUID()

        CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        ).record(sessionCode: "8abc", forWorkspaceID: workspaceID)

        let restored = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(restored.sessionCode(forWorkspaceID: workspaceID) == "8ABC")
    }

    @Test
    func updatingOneWorkspaceKeepsOtherWorkspaceBindings() throws {
        let store = try makeStore()
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()

        store.record(sessionCode: "aaaa", forWorkspaceID: firstWorkspaceID)
        store.record(sessionCode: "bbbb", forWorkspaceID: secondWorkspaceID)
        store.record(sessionCode: "cccc", forWorkspaceID: firstWorkspaceID)

        #expect(store.sessionCode(forWorkspaceID: firstWorkspaceID) == "CCCC")
        #expect(store.sessionCode(forWorkspaceID: secondWorkspaceID) == "BBBB")
    }

    @Test
    func removingWorkspaceBindingKeepsOtherWorkspaceBindings() throws {
        let store = try makeStore()
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()

        store.record(sessionCode: "aaaa", forWorkspaceID: firstWorkspaceID)
        store.record(sessionCode: "bbbb", forWorkspaceID: secondWorkspaceID)
        store.remove(workspaceID: firstWorkspaceID)

        #expect(store.sessionCode(forWorkspaceID: firstWorkspaceID) == nil)
        #expect(store.sessionCode(forWorkspaceID: secondWorkspaceID) == "BBBB")
    }

    @Test
    func blankSessionCodesAreIgnored() throws {
        let store = try makeStore()
        let workspaceID = UUID()

        store.record(sessionCode: "   ", forWorkspaceID: workspaceID)

        #expect(store.sessionCode(forWorkspaceID: workspaceID) == nil)
        #expect(store.bindingsByWorkspaceID().isEmpty)
    }

    @Test
    func removeAllClearsEveryWorkspaceBinding() throws {
        let store = try makeStore()
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()

        store.record(sessionCode: "aaaa", forWorkspaceID: firstWorkspaceID)
        store.record(sessionCode: "bbbb", forWorkspaceID: secondWorkspaceID)
        store.removeAll()

        #expect(store.sessionCode(forWorkspaceID: firstWorkspaceID) == nil)
        #expect(store.sessionCode(forWorkspaceID: secondWorkspaceID) == nil)
        #expect(store.bindingsByWorkspaceID().isEmpty)
    }

    @Test
    func malformedPersistedPayloadIsTreatedAsEmpty() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "workspace-sessions")
        let store = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(store.bindingsByWorkspaceID().isEmpty)
    }

    @Test
    func persistedLegacyCodesAreNormalizedOnRead() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspaceID = UUID()
        let persisted = [
            CollaborationWorkspaceSessionBinding(
                workspaceID: workspaceID,
                sessionCode: "5z-nh"
            ),
        ]
        defaults.set(try JSONEncoder().encode(persisted), forKey: "workspace-sessions")
        let store = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(store.sessionCode(forWorkspaceID: workspaceID) == "5ZNH")
    }

    @Test
    func invalidPersistedBindingCodesAreSkipped() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let blankWorkspaceID = UUID()
        let validWorkspaceID = UUID()
        let persisted = [
            CollaborationWorkspaceSessionBinding(
                workspaceID: blankWorkspaceID,
                sessionCode: " "
            ),
            CollaborationWorkspaceSessionBinding(
                workspaceID: validWorkspaceID,
                sessionCode: "zzzz"
            ),
        ]
        defaults.set(try JSONEncoder().encode(persisted), forKey: "workspace-sessions")
        let store = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(store.sessionCode(forWorkspaceID: blankWorkspaceID) == nil)
        #expect(store.sessionCode(forWorkspaceID: validWorkspaceID) == "ZZZZ")
        #expect(store.bindingsByWorkspaceID().count == 1)
    }

    @Test
    func laterPersistedDuplicateBindingWinsForWorkspace() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspaceID = UUID()
        let persisted = [
            CollaborationWorkspaceSessionBinding(
                workspaceID: workspaceID,
                sessionCode: "aaaa"
            ),
            CollaborationWorkspaceSessionBinding(
                workspaceID: workspaceID,
                sessionCode: "bbbb"
            ),
        ]
        defaults.set(try JSONEncoder().encode(persisted), forKey: "workspace-sessions")
        let store = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(store.sessionCode(forWorkspaceID: workspaceID) == "BBBB")
        #expect(store.bindingsByWorkspaceID().count == 1)
    }

    @Test
    func separateWorkspacesCanBindToSeparateSessions() throws {
        let store = try makeStore()
        let workspaceIDs = [UUID(), UUID(), UUID()]

        store.record(sessionCode: "aaaa", forWorkspaceID: workspaceIDs[0])
        store.record(sessionCode: "bbbb", forWorkspaceID: workspaceIDs[1])
        store.record(sessionCode: "cccc", forWorkspaceID: workspaceIDs[2])

        #expect(store.sessionCode(forWorkspaceID: workspaceIDs[0]) == "AAAA")
        #expect(store.sessionCode(forWorkspaceID: workspaceIDs[1]) == "BBBB")
        #expect(store.sessionCode(forWorkspaceID: workspaceIDs[2]) == "CCCC")
        #expect(store.bindingsByWorkspaceID().count == 3)
    }

    @Test
    func unknownWorkspaceReturnsNilWithoutChangingStoredBindings() throws {
        let store = try makeStore()
        let knownWorkspaceID = UUID()
        let unknownWorkspaceID = UUID()

        store.record(sessionCode: "aaaa", forWorkspaceID: knownWorkspaceID)

        #expect(store.sessionCode(forWorkspaceID: unknownWorkspaceID) == nil)
        #expect(store.sessionCode(forWorkspaceID: knownWorkspaceID) == "AAAA")
        #expect(store.bindingsByWorkspaceID().count == 1)
    }

    @Test
    func removedBindingStaysRemovedAcrossStoreInstances() throws {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()
        let store = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        store.record(sessionCode: "aaaa", forWorkspaceID: firstWorkspaceID)
        store.record(sessionCode: "bbbb", forWorkspaceID: secondWorkspaceID)
        store.remove(workspaceID: firstWorkspaceID)

        let restored = CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )

        #expect(restored.sessionCode(forWorkspaceID: firstWorkspaceID) == nil)
        #expect(restored.sessionCode(forWorkspaceID: secondWorkspaceID) == "BBBB")
    }

    private func makeStore() throws -> CollaborationWorkspaceSessionStore {
        let suite = "cmux-collaboration-workspace-session-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CollaborationWorkspaceSessionStore(
            defaults: defaults,
            workspaceSessionBindingsKey: "workspace-sessions",
            inviteCodeStore: CollaborationInviteCodeStore(defaults: defaults)
        )
    }
}
