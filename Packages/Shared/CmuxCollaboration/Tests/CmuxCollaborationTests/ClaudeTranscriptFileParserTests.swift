import Foundation
import Testing
@testable import CmuxCollaboration

@Suite
struct ClaudeTranscriptFileParserTests {
    private func line(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    @Test
    func parsesUserStringAndAssistantBlockContent() throws {
        let jsonl = [
            line([
                "type": "user",
                "uuid": "u-1",
                "timestamp": "2026-07-04T10:00:00.000Z",
                "message": ["role": "user", "content": "the british are coming"],
            ]),
            line([
                "type": "assistant",
                "uuid": "a-1",
                "timestamp": "2026-07-04T10:00:05Z",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": "Understood."],
                        ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]],
                    ],
                ],
            ]),
        ].joined(separator: "\n")

        let turns = ClaudeTranscriptFileParser.parseTurns(jsonl: jsonl, limit: 10)
        #expect(turns.count == 2)
        #expect(turns[0].id == "u-1")
        #expect(turns[0].role == .user)
        #expect(turns[0].text == "the british are coming")
        #expect(turns[0].timestamp != nil)
        #expect(turns[1].id == "a-1")
        #expect(turns[1].role == .assistant)
        #expect(turns[1].text == "Understood.")
        #expect(turns[1].timestamp != nil)
    }

    @Test
    func skipsMetaSidechainToolOnlyAndCommandEchoLines() throws {
        let jsonl = [
            line(["type": "summary", "summary": "Session summary"]),
            line([
                "type": "user",
                "uuid": "meta-1",
                "isMeta": true,
                "message": ["role": "user", "content": "Caveat: internal"],
            ]),
            line([
                "type": "assistant",
                "uuid": "side-1",
                "isSidechain": true,
                "message": ["role": "assistant", "content": [["type": "text", "text": "subagent chatter"]]],
            ]),
            line([
                "type": "user",
                "uuid": "tool-1",
                "message": [
                    "role": "user",
                    "content": [["type": "tool_result", "tool_use_id": "t1", "content": "ok"]],
                ],
            ]),
            line([
                "type": "user",
                "uuid": "cmd-1",
                "message": ["role": "user", "content": "<command-name>/clear</command-name>"],
            ]),
            line([
                "type": "user",
                "uuid": "real-1",
                "message": ["role": "user", "content": "actual message"],
            ]),
        ].joined(separator: "\n")

        let turns = ClaudeTranscriptFileParser.parseTurns(jsonl: jsonl, limit: 10)
        #expect(turns.map(\.id) == ["real-1"])
    }

    @Test
    func limitKeepsOnlyTheMostRecentTurns() throws {
        let jsonl = (1...5).map { index in
            line([
                "type": "user",
                "uuid": "u-\(index)",
                "message": ["role": "user", "content": "message \(index)"],
            ])
        }.joined(separator: "\n")

        let turns = ClaudeTranscriptFileParser.parseTurns(jsonl: jsonl, limit: 2)
        #expect(turns.map(\.id) == ["u-4", "u-5"])
    }

    @Test
    func fileTailReadDropsTruncatedFirstLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-transcript-parser-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("session.jsonl")

        let lines = (1...20).map { index in
            line([
                "type": "user",
                "uuid": "u-\(index)",
                "message": ["role": "user", "content": "message \(index) " + String(repeating: "x", count: 200)],
            ])
        }
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)

        // A tail window smaller than the file forces a mid-line start; the
        // fragment must be dropped, not parsed as garbage, and the newest
        // turns must still come through.
        let turns = ClaudeTranscriptFileParser.parseTurns(fileURL: fileURL, limit: 3, maxTailBytes: 1_000)
        #expect(turns.count == 3)
        #expect(turns.last?.id == "u-20")
    }

    @Test
    func ingestedTurnsDedupeBySourceIDAcrossRepeatedBackfills() async throws {
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1", deliveryPolicy: .semiLive)
        let jsonl = line([
            "type": "user",
            "uuid": "u-1",
            "message": ["role": "user", "content": "the british are coming"],
        ])
        let turns = ClaudeTranscriptFileParser.parseTurns(jsonl: jsonl, limit: 10)

        // Simulate wire-time backfill running twice (re-wire): same sourceID,
        // so the transcript index and the promoted ledger stay single-entry.
        for _ in 0..<2 {
            for turn in turns {
                _ = await store.appendTranscriptTurn(
                    roomID: "room-1",
                    agentKind: "claude",
                    surfaceID: "surface-a",
                    role: turn.role,
                    text: turn.text,
                    sourceID: "session-1:\(turn.id)"
                )
            }
        }
        let indexed = await store.transcriptTurns(roomID: "room-1", surfaceID: "surface-a")
        #expect(indexed.count == 1)
    }
}
