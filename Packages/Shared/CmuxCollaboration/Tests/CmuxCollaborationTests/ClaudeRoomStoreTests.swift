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
    func connectingTwoSurfacesKeepsBothMembers() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")

        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        let room = await store.connect(
            member: ClaudeRoomMember(id: "m-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )

        #expect(Set(room.members.map(\.surfaceID)) == ["surface-a", "surface-b"])
    }

    @Test
    func disconnectingOneSurfaceLeavesTheOther() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )

        let room = try #require(await store.disconnect(roomID: "room-1", memberID: "m-a", surfaceID: "surface-a"))

        #expect(room.members.map(\.surfaceID) == ["surface-b"])
    }

    @Test
    func reconnectingSameSurfaceDoesNotDuplicateMember() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer", displayName: "A"),
            to: "room-1"
        )
        let room = await store.connect(
            member: ClaudeRoomMember(id: "m-a2", surfaceID: "surface-a", peerID: "peer", displayName: "A renamed"),
            to: "room-1"
        )

        #expect(room.members.count == 1)
        #expect(room.members.first?.displayName == "A renamed")
    }

    @Test
    func movingSurfaceBetweenRoomsLeavesOldRoomEmpty() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.createRoom(id: "room-2")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )

        // Runtime drops the old membership before joining the new room.
        _ = await store.disconnect(roomID: "room-1", memberID: "m-a", surfaceID: "surface-a")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-2"
        )

        let roomOne = try #require(await store.room(id: "room-1"))
        let roomTwo = try #require(await store.room(id: "room-2"))
        #expect(roomOne.members.isEmpty)
        #expect(roomTwo.members.map(\.surfaceID) == ["surface-a"])
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

    @Test
    func transcriptSearchIsQueryableAcrossAgents() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .assistant,
            text: "Claude confirmed AgentResumeArgv routes resumes through the wrapper."
        )
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "codex",
            memberID: "member-b",
            surfaceID: "surface-b",
            role: .assistant,
            text: "Codex found the transcript parser tests."
        )

        let results = await store.searchTranscripts(roomID: "room-1", query: "wrapper", limit: 10)

        #expect(results.map(\.agentKind) == ["claude"])
        #expect(results.first?.text.contains("AgentResumeArgv") == true)
    }

    @Test
    func contextPackScopesLedgerAndTranscriptHistory() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.appendEvent(roomID: "room-1", kind: .decision, text: "Use a room ledger.")
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .handoff,
            targetMemberIDs: ["member-b"],
            text: "Codex should review the context compiler."
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .blocker,
            targetMemberIDs: ["member-c"],
            text: "Unrelated blocked task."
        )
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .assistant,
            text: "The compiler should not inject the whole transcript."
        )

        let pack = try #require(await store.contextPack(
            roomID: "room-1",
            memberID: "member-b",
            sinceEventSequence: 0,
            transcriptQuery: "whole transcript",
            maxEvents: 10,
            maxTranscriptTurns: 5
        ))

        #expect(pack.events.map(\.kind) == [.decision, .handoff])
        #expect(pack.transcriptTurns.map(\.agentKind) == ["claude"])
        #expect(pack.promptText.contains("Use a room ledger."))
        #expect(!pack.promptText.contains("Unrelated blocked task."))
    }

    @Test
    func activeDispatchOnlyPromptsTargetedInterruptEvents() {
        let builder = AgentRoomActiveDispatchPromptBuilder(maxTextCharacters: 20)
        let handoff = ClaudeRoomEvent(
            sequence: 1,
            roomID: "room-1",
            kind: .handoff,
            fromSurfaceID: "surface-a",
            targetSurfaceIDs: ["surface-b"],
            text: "Build the contact page and report back with tests."
        )
        let summary = ClaudeRoomEvent(
            sequence: 2,
            roomID: "room-1",
            kind: .summary,
            fromSurfaceID: "surface-a",
            targetSurfaceIDs: ["surface-b"],
            text: "Finished a normal turn."
        )
        let untargetedQuestion = ClaudeRoomEvent(
            sequence: 3,
            roomID: "room-1",
            kind: .question,
            text: "Should anyone answer this?"
        )

        #expect(builder.shouldDispatch(handoff))
        #expect(builder.prompt(for: handoff)?.contains("Shared room handoff from surface surface-a") == true)
        #expect(builder.prompt(for: handoff)?.contains("Build the contact pa...") == true)
        #expect(!builder.shouldDispatch(summary))
        #expect(builder.prompt(for: summary) == nil)
        #expect(!builder.shouldDispatch(untargetedQuestion))
        #expect(builder.prompt(for: untargetedQuestion) == nil)
    }
}
