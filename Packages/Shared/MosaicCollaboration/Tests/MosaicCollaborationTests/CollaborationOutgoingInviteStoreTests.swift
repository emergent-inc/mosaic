import MosaicCollaboration
import Foundation
import Testing

@Suite(.serialized)
struct CollaborationOutgoingInviteStoreTests {
    @Test func recordsDescriptorAndInvitees() throws {
        let store = try makeStore()

        store.recordDescriptor("desc-1", forRoomKey: "ROOM1")
        store.addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")
        store.addInvitee("user-b", forRoomKey: "ROOM1", descriptor: "desc-1")

        let record = try #require(store.record(forRoomKey: "ROOM1"))
        #expect(record.descriptor == "desc-1")
        #expect(record.inviteeUserIDs == ["user-a", "user-b"])
    }

    @Test func addingInviteeIsIdempotent() throws {
        let store = try makeStore()

        store.addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")
        store.addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")

        #expect(store.record(forRoomKey: "ROOM1")?.inviteeUserIDs == ["user-a"])
    }

    @Test func recordingDescriptorPreservesExistingInvitees() throws {
        let store = try makeStore()

        store.addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")
        store.recordDescriptor("desc-1", forRoomKey: "ROOM1")

        #expect(store.record(forRoomKey: "ROOM1")?.inviteeUserIDs == ["user-a"])
    }

    @Test func persistsAcrossStoreInstances() throws {
        let suite = "mosaic-collaboration-outgoing-invites-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        CollaborationOutgoingInviteStore(defaults: defaults, storageKey: "outgoing")
            .addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")

        let restored = CollaborationOutgoingInviteStore(defaults: defaults, storageKey: "outgoing")
        let record = try #require(restored.record(forRoomKey: "ROOM1"))
        #expect(record.descriptor == "desc-1")
        #expect(record.inviteeUserIDs == ["user-a"])
    }

    @Test func removeReturnsAndClearsTheRecord() throws {
        let store = try makeStore()
        store.addInvitee("user-a", forRoomKey: "ROOM1", descriptor: "desc-1")
        store.addInvitee("user-c", forRoomKey: "ROOM2", descriptor: "desc-2")

        let removed = store.remove(forRoomKey: "ROOM1")

        #expect(removed?.descriptor == "desc-1")
        #expect(removed?.inviteeUserIDs == ["user-a"])
        #expect(store.record(forRoomKey: "ROOM1") == nil)
        // Other rooms are untouched.
        #expect(store.record(forRoomKey: "ROOM2")?.descriptor == "desc-2")
    }

    @Test func ignoresEmptyInputs() throws {
        let store = try makeStore()

        store.recordDescriptor("", forRoomKey: "ROOM1")
        store.addInvitee("   ", forRoomKey: "ROOM1", descriptor: "desc-1")
        store.addInvitee("user-a", forRoomKey: "", descriptor: "desc-1")

        #expect(store.records().isEmpty)
    }

    @Test func malformedPersistedPayloadIsTreatedAsEmpty() throws {
        let suite = "mosaic-collaboration-outgoing-invites-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "outgoing")

        let store = CollaborationOutgoingInviteStore(defaults: defaults, storageKey: "outgoing")
        #expect(store.records().isEmpty)
    }

    private func makeStore() throws -> CollaborationOutgoingInviteStore {
        let suite = "mosaic-collaboration-outgoing-invites-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CollaborationOutgoingInviteStore(defaults: defaults, storageKey: "outgoing")
    }
}
