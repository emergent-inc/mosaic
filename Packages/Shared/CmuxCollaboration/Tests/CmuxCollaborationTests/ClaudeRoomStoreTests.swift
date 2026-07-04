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
    func transcriptTurnsDeduplicateBySourceID() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        let first = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .assistant,
            text: "First indexed copy.",
            sourceID: "session-a:line-1"
        )
        let duplicate = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .assistant,
            text: "Duplicate replay should be ignored.",
            sourceID: "session-a:line-1"
        )

        let turns = await store.transcriptTurns(roomID: "room-1", limit: 10)

        #expect(duplicate == first)
        #expect(turns.map(\.text) == ["First indexed copy."])
    }

    @Test
    func peerContextPackExcludesRecipientTranscriptHistory() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .assistant,
            text: "Claude A already diagnosed the failing hook path."
        )
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "codex",
            memberID: "member-b",
            surfaceID: "surface-b",
            role: .assistant,
            text: "Codex B should not receive its own prior answer."
        )

        let pack = try #require(await store.peerContextPack(
            roomID: "room-1",
            recipientMemberID: "member-b",
            recipientSurfaceID: "surface-b",
            maxEvents: 0,
            maxTranscriptTurns: 10
        ))

        #expect(pack.transcriptTurns.map(\.surfaceID) == ["surface-a"])
        #expect(pack.promptText.contains("failing hook path"))
        #expect(!pack.promptText.contains("own prior answer"))
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

    @Test
    func liveRoomBroadcastsPlainMessagesButManualDoesNot() {
        let builder = AgentRoomActiveDispatchPromptBuilder(maxTextCharacters: 40)
        let message = ClaudeRoomEvent(
            sequence: 1,
            roomID: "room-1",
            kind: .message,
            fromSurfaceID: "surface-a",
            text: "the british are coming"
        )

        // A plain message broadcasts only when the room is live.
        #expect(builder.shouldBroadcast(message, policy: .semiLive))
        #expect(!builder.shouldBroadcast(message, policy: .manual))

        // Broadcast prompt carries the relay header and the message text.
        let prompt = builder.broadcastPrompt(for: message, policy: .semiLive)
        #expect(prompt?.contains("Shared room message from surface surface-a") == true)
        #expect(prompt?.contains("the british are coming") == true)
        #expect(builder.broadcastPrompt(for: message, policy: .manual) == nil)

        // Summaries never broadcast, even in a live room, to avoid runaway chatter.
        let summary = ClaudeRoomEvent(
            sequence: 2,
            roomID: "room-1",
            kind: .summary,
            fromSurfaceID: "surface-a",
            text: "Finished a normal turn."
        )
        #expect(!builder.shouldBroadcast(summary, policy: .semiLive))
        #expect(builder.broadcastPrompt(for: summary, policy: .semiLive) == nil)
    }

    @Test
    func relayPromptDetectionMatchesInjectedHeadersOnly() {
        // Every header the builder can inject must be recognized as a relay prompt.
        #expect(AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("Shared room message from surface surface-a:\nhi"))
        #expect(AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("Shared room handoff from surface surface-a:\ndo x"))
        #expect(AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("Shared room question from surface surface-a:\nq"))
        #expect(AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("Shared room blocker from surface surface-a:\nb"))
        // Leading whitespace is tolerated.
        #expect(AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("   Shared room message from surface s:\nhi"))
        // Ordinary user prompts are not treated as relays.
        #expect(!AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("the british are coming"))
        #expect(!AgentRoomActiveDispatchPromptBuilder.isRelayPrompt("Please review the shared room"))
    }

    @Test
    func setDeliveryPolicyUpdatesRoom() async {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1", deliveryPolicy: .manual)
        let updated = await store.setDeliveryPolicy(roomID: "room-1", policy: .semiLive)
        #expect(updated.deliveryPolicy == .semiLive)
        #expect(await store.room(id: "room-1")?.deliveryPolicy == .semiLive)
    }

    @Test
    func appendEventDeduplicatesBySourceID() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        let first = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromSurfaceID: "surface-a",
            text: "the british are coming",
            sourceID: "session-a:msg-1"
        )
        let duplicate = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromSurfaceID: "surface-a",
            text: "the british are coming (replayed)",
            sourceID: "session-a:msg-1"
        )
        #expect(first.event.sequence == 1)
        #expect(duplicate.event == first.event)
        #expect(await store.room(id: "room-1")?.events.count == 1)

        // A different sourceID is a genuinely new event.
        let second = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromSurfaceID: "surface-a",
            text: "reinforcements incoming",
            sourceID: "session-a:msg-2"
        )
        #expect(second.event.sequence == 2)
        #expect(await store.room(id: "room-1")?.events.count == 2)
    }

    @Test
    func wireTimeBackfillSyncsJoiningPeerOnceWithoutReinterruptingExisting() async throws {
        // Simulates the store-level effect of backfillAgentRoomLedgerFromTranscripts:
        // seed the ledger from the seeding peer's transcript, then advance the
        // existing member's cursor while leaving the joining member behind.
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1", deliveryPolicy: .semiLive)
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        // Existing peer A has already caught up to the current (empty) ledger.
        _ = await store.acknowledge(roomID: "room-1", memberID: "member-a", sequence: 0)

        // Peer B wires in; backfill promotes A's pre-wire transcript into the ledger.
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-a",
            fromSurfaceID: "surface-a",
            text: "the british are coming",
            sourceID: "session-a:msg-1"
        )
        let room = try #require(await store.room(id: "room-1"))
        // Existing member A's cursor advances past the backfill; B is left behind.
        _ = await store.acknowledge(roomID: "room-1", memberID: "member-a", sequence: room.lastSequence)

        // Joining peer B receives the prior conversation exactly once.
        let joined = await store.consumePendingEvents(roomID: "room-1", memberID: "member-b", surfaceID: "surface-b")
        #expect(joined.map(\.text) == ["the british are coming"])
        #expect(await store.consumePendingEvents(roomID: "room-1", memberID: "member-b", surfaceID: "surface-b").isEmpty)

        // Existing peer A is not re-interrupted with the backfilled history.
        let existing = await store.consumePendingEvents(roomID: "room-1", memberID: "member-a", surfaceID: "surface-a")
        #expect(existing.isEmpty)

        // Re-wiring B (backfill re-runs) does not duplicate the ledger event.
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-a",
            fromSurfaceID: "surface-a",
            text: "the british are coming",
            sourceID: "session-a:msg-1"
        )
        #expect(await store.room(id: "room-1")?.events.count == 1)
    }

    @Test
    func consumeSelfHealsFromPeerTranscriptWhenLedgerBacklogEmpty() async throws {
        // Models agentRoomConsumePendingForAutomation's self-heal: even when the
        // wire-time backfill produced no ledger events (the peer's liveSession was
        // not warm at connect), the peer's ingested transcript turns are promoted
        // into the ledger at consume time and delivered to the recipient exactly
        // once, with no re-spam on later idle/prompt hooks.
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1", deliveryPolicy: .semiLive)
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )
        // Peer A's pre-wire message exists only in the transcript index; the
        // ledger is empty, so the old empty-backlog bail would deliver nothing.
        _ = await store.appendTranscriptTurn(
            roomID: "room-1",
            agentKind: "claude",
            memberID: "member-a",
            surfaceID: "surface-a",
            role: .user,
            text: "the british are coming",
            sourceID: "session-a:msg-1"
        )
        #expect(await store.room(id: "room-1")?.events.isEmpty == true)

        // The self-heal step: promote each peer transcript turn to the ledger,
        // then drain for the recipient. Mirrors promoteTranscriptTurnsToLedger +
        // consumePendingEvents in agentRoomConsumePendingForAutomation.
        func promoteAndConsume() async -> [ClaudeRoomEvent] {
            for turn in await store.transcriptTurns(roomID: "room-1", limit: 10) {
                _ = await store.appendEvent(
                    roomID: "room-1",
                    kind: .message,
                    fromMemberID: turn.memberID,
                    fromSurfaceID: turn.surfaceID,
                    text: turn.text,
                    sourceID: turn.sourceID
                )
            }
            return await store.consumePendingEvents(
                roomID: "room-1",
                memberID: "member-b",
                surfaceID: "surface-b"
            )
        }

        let delivered = await promoteAndConsume()
        #expect(delivered.map(\.text) == ["the british are coming"])

        // A later hook re-runs promote+consume: sourceID dedup holds the ledger at
        // one event and the advanced cursor yields nothing new (no spam).
        let again = await promoteAndConsume()
        #expect(again.isEmpty)
        #expect(await store.room(id: "room-1")?.events.count == 1)
    }

    @Test
    func consumePendingEventsAdvancesCursorAndScopesToRecipient() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        _ = await store.connect(
            member: ClaudeRoomMember(id: "member-b", surfaceID: "surface-b", peerID: "peer"),
            to: "room-1"
        )

        // A peer message, this recipient's own message, and a message targeted at a
        // third surface. Only the peer message should reach surface-b.
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-a",
            fromSurfaceID: "surface-a",
            text: "the british are coming"
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-b",
            fromSurfaceID: "surface-b",
            text: "b's own message"
        )
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-a",
            fromSurfaceID: "surface-a",
            targetSurfaceIDs: ["surface-c"],
            text: "targeted at c only"
        )

        let firstPass = await store.consumePendingEvents(
            roomID: "room-1",
            memberID: "member-b",
            surfaceID: "surface-b"
        )
        #expect(firstPass.map(\.text) == ["the british are coming"])

        // Cursor advanced to lastSequence: nothing pending on a second drain.
        let secondPass = await store.consumePendingEvents(
            roomID: "room-1",
            memberID: "member-b",
            surfaceID: "surface-b"
        )
        #expect(secondPass.isEmpty)

        // A newly shared peer message is delivered exactly once afterward.
        _ = await store.appendEvent(
            roomID: "room-1",
            kind: .message,
            fromMemberID: "member-a",
            fromSurfaceID: "surface-a",
            text: "reinforcements incoming"
        )
        let thirdPass = await store.consumePendingEvents(
            roomID: "room-1",
            memberID: "member-b",
            surfaceID: "surface-b"
        )
        #expect(thirdPass.map(\.text) == ["reinforcements incoming"])
        #expect(await store.consumePendingEvents(roomID: "room-1", memberID: "member-b", surfaceID: "surface-b").isEmpty)
    }
}
