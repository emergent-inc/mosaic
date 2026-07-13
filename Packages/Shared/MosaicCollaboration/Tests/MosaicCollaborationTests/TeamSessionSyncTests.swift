import Foundation
import Testing
@testable import MosaicCollaboration

@Suite("TeamSessionSync helpers")
struct TeamSessionSyncTests {
    @Test
    func wipRefAndHandoffBranchEmbedTheSessionId() {
        #expect(
            TeamSessionSync.wipRefName(sessionId: "0e9f3a52-aaaa-bbbb-cccc-ddddeeeeffff")
                == "refs/mosaic/sessions/0e9f3a52-aaaa-bbbb-cccc-ddddeeeeffff"
        )
        #expect(
            TeamSessionSync.handoffBranchName(sessionId: "0e9f3a52-aaaa-bbbb-cccc-ddddeeeeffff")
                == "mosaic/handoff-0e9f3a52"
        )
    }

    @Test
    func claudeProjectDirEncodingReplacesSlashesAndDots() {
        #expect(TeamSessionSync.encodeClaudeProjectDir("/Users/x/repo") == "-Users-x-repo")
        #expect(TeamSessionSync.encodeClaudeProjectDir("/Users/x/repo/.claude") == "-Users-x-repo--claude")
    }
}

@Suite("TeamSessionTranscriptSummary")
struct TeamSessionTranscriptSummaryTests {
    private func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    @Test
    func summarizesTitleModelAndTurnCount() {
        let jsonl = [
            line(["type": "user", "message": ["role": "user", "content": "Fix the login bug"]]),
            line([
                "type": "assistant",
                "message": ["role": "assistant", "model": "claude-opus-4", "content": []],
            ]),
            line(["type": "user", "message": ["role": "user", "content": "now add a test"]]),
            line([
                "type": "assistant",
                "message": ["role": "assistant", "model": "claude-opus-5", "content": []],
            ]),
        ].joined(separator: "\n")

        let summary = TeamSessionTranscriptSummary.summarize(jsonl: jsonl)

        #expect(summary.title == "Fix the login bug")
        #expect(summary.model == "claude-opus-5")
        #expect(summary.turnCount == 2)
    }

    @Test
    func skipsSyntheticUserEntriesAndSidechains() {
        let jsonl = [
            line(["type": "user", "isSidechain": true, "message": ["content": "internal subagent prompt"]]),
            line(["type": "user", "message": ["content": "<command-name>ls</command-name>"]]),
            line(["type": "user", "message": ["content": "[Request interrupted by user]"]]),
            line(["type": "user", "message": ["content": "Real question here"]]),
        ].joined(separator: "\n")

        let summary = TeamSessionTranscriptSummary.summarize(jsonl: jsonl)

        #expect(summary.title == "Real question here")
        #expect(summary.turnCount == 3)
    }

    @Test
    func readsStructuredContentBlocksAndSurvivesMalformedLines() {
        let jsonl = [
            "{not json",
            line([
                "type": "user",
                "message": ["content": [["type": "text", "text": "Structured message"]]],
            ]),
            "",
        ].joined(separator: "\n")

        let summary = TeamSessionTranscriptSummary.summarize(jsonl: jsonl)

        #expect(summary.title == "Structured message")
        #expect(summary.turnCount == 1)
    }

    @Test
    func truncatesLongTitlesToOneLine() {
        let longFirstLine = String(repeating: "a", count: 200)
        let jsonl = line(["type": "user", "message": ["content": longFirstLine + "\nsecond line"]])

        let summary = TeamSessionTranscriptSummary.summarize(jsonl: jsonl)

        #expect(summary.title?.count == 121)
        #expect(summary.title?.hasSuffix("…") == true)
    }
}

@Suite("TeamSessionTranscriptRewriter")
struct TeamSessionTranscriptRewriterTests {
    @Test
    func rewritesTopLevelCwdAndNestedPaths() throws {
        let jsonl = [
            #"{"type":"user","cwd":"/Users/alex/dev/app","message":{"content":"hi"}}"#,
            #"{"type":"assistant","cwd":"/Users/alex/dev/app/sub","message":{"content":[]}}"#,
            #"{"type":"user","cwd":"/Users/alex/other","message":{"content":"unrelated"}}"#,
        ].joined(separator: "\n")

        let rewritten = TeamSessionTranscriptRewriter.rewritingCwd(
            jsonl: jsonl,
            from: "/Users/alex/dev/app",
            to: "/Users/blake/code/app"
        )

        func recordedCwd(_ line: String) throws -> String? {
            let data = try #require(line.data(using: .utf8))
            let record = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return record["cwd"] as? String
        }

        let lines = rewritten.split(separator: "\n").map(String.init)
        #expect(try recordedCwd(lines[0]) == "/Users/blake/code/app")
        #expect(try recordedCwd(lines[1]) == "/Users/blake/code/app/sub")
        #expect(try recordedCwd(lines[2]) == "/Users/alex/other")
    }

    @Test
    func passesThroughWhenPathsMatchOrLinesAreMalformed() {
        let jsonl = "{broken\n" + #"{"type":"user","cwd":"/same"}"#

        #expect(
            TeamSessionTranscriptRewriter.rewritingCwd(jsonl: jsonl, from: "/same", to: "/same") == jsonl
        )
        let rewritten = TeamSessionTranscriptRewriter.rewritingCwd(
            jsonl: jsonl,
            from: "/other",
            to: "/elsewhere"
        )
        #expect(rewritten.hasPrefix("{broken"))
    }

    @Test
    func doesNotRewritePrefixCollisionsOutsideTheCheckout() {
        let jsonl = #"{"type":"user","cwd":"/Users/alex/dev/app-extras"}"#

        let rewritten = TeamSessionTranscriptRewriter.rewritingCwd(
            jsonl: jsonl,
            from: "/Users/alex/dev/app",
            to: "/Users/blake/code/app"
        )

        #expect(rewritten == jsonl)
    }
}
