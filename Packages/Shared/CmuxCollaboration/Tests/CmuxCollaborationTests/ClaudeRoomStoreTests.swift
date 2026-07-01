import Foundation
import Testing
@testable import CmuxCollaboration

@Suite
struct ClaudeRoomStoreTests {
    @Test
    func connectMemberAndAppendEvent() async throws {
        let store = ClaudeRoomStore()
        let room = await store.createRoom(id: "room-1", title: "Demo", deliveryPolicy: .manual)
        #expect(room.id == "room-1")

        let member = ClaudeRoomMember(surfaceID: "surface-a", peerID: "peer-a", displayName: "A")
        let connected = await store.connect(member: member, to: "room-1")
        #expect(connected.members.map(\.surfaceID) == ["surface-a"])

        let result = await store.appendEvent(
            roomID: "room-1",
            kind: .summary,
            fromSurfaceID: "surface-a",
            text: "Implemented the parser."
        )

        #expect(result.event.sequence == 1)
        #expect(result.room.events.map(\.text) == ["Implemented the parser."])
    }

    @Test
    func digestUsesCursorAndLimitsEvents() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.appendEvent(roomID: "room-1", kind: .summary, text: "one")
        _ = await store.appendEvent(roomID: "room-1", kind: .task, text: "two")
        _ = await store.appendEvent(roomID: "room-1", kind: .status, text: "three")

        let room = try #require(await store.room(id: "room-1"))
        let digest = ClaudeRoomDigestBuilder(maxEvents: 2).digest(for: room, since: 1)

        #expect(digest.contains("[2] task: two"))
        #expect(digest.contains("[3] status: three"))
        #expect(!digest.contains("one"))
    }

    @Test
    func turnSummaryCarriesTranscriptCursorRange() {
        let summary = ClaudeRoomTurnSummaryBuilder(maxCharacters: 12).summary(
            surfaceID: "surface-a",
            startSequence: 4,
            endSequence: 8,
            text: "  finished the parser and tests  "
        )

        #expect(summary == "surface surface-a transcript 4-8: finished the...")
    }
}
