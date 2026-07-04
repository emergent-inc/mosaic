import Foundation
import Testing
@testable import CmuxCollaboration

@Suite
struct ClaudeRoomStorePersistenceTests {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-room-store-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("agent-rooms.json", isDirectory: false)
    }

    @Test
    func roomsMembersEventsAndCursorsSurviveRestart() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClaudeRoomStore(persistenceURL: url)
        _ = await store.createRoom(id: "room-1", title: "Demo", deliveryPolicy: .semiLive)
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "m-a",
            fromSurfaceID: "surface-a",
            text: "the british are coming",
            sourceID: "turn-1"
        )
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "m-a",
            surfaceID: "surface-a",
            role: .user,
            text: "the british are coming",
            sourceID: "session:turn-1"
        )
        // m-b drains the backlog, advancing its cursor to the latest sequence.
        let drained = await store.consumePendingEvents(roomID: "room-1", memberID: "m-b")
        #expect(drained.map(\.text) == ["the british are coming"])

        // Simulate an app relaunch: a brand-new store instance on the same file.
        let reloaded = ClaudeRoomStore(persistenceURL: url)
        let room = try #require(await reloaded.room(id: "room-1"))
        #expect(room.deliveryPolicy == .semiLive)
        #expect(Set(room.members.map(\.surfaceID)) == ["surface-a", "surface-b"])
        #expect(room.events.map(\.text) == ["the british are coming"])
        #expect(room.lastSequence == 1)

        // The acknowledgment cursor survived, so the message is NOT re-delivered
        // after restart (the exact re-spam bug persistence must not reintroduce).
        let afterRestart = await reloaded.consumePendingEvents(roomID: "room-1", memberID: "m-b")
        #expect(afterRestart.isEmpty)

        // The transcript index survived too, so wire-time backfill dedupe
        // (by sourceID) still holds across restarts.
        let turns = await reloaded.transcriptTurns(roomID: "room-1", surfaceID: "surface-a")
        #expect(turns.map(\.sourceID) == ["session:turn-1"])
    }

    @Test
    func reconnectingASurfaceKeepsItsAcknowledgmentCursor() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClaudeRoomStore(persistenceURL: url)
        _ = await store.createRoom(id: "room-1", deliveryPolicy: .semiLive)
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "m-a",
            fromSurfaceID: "surface-a",
            text: "seen once"
        )
        _ = await store.consumePendingEvents(roomID: "room-1", memberID: "m-b")

        // Re-wiring the same surface (fresh member value, nil cursor) must not
        // reset the cursor and replay the backlog.
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        let replayed = await store.consumePendingEvents(roomID: "room-1", memberID: "m-b")
        #expect(replayed.isEmpty)
    }

    @Test
    func storeWithoutPersistenceURLWritesNothing() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        // Nothing to assert on disk; this guards against a crash/regression in
        // the nil-URL path (persist() must be a no-op).
        let room = await store.room(id: "room-1")
        #expect(room != nil)
    }
}
