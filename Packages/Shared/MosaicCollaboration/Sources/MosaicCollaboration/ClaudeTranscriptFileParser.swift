public import Foundation

/// One conversational turn extracted from a Claude Code transcript JSONL file.
public struct ClaudeTranscriptFileTurn: Sendable, Equatable {
    /// Stable transcript line identifier (the line's `uuid`), used as the
    /// dedup `sourceID` when ingesting into a room.
    public let id: String
    /// Speaker role.
    public let role: AgentRoomTranscriptRole
    /// Plain conversational text of the turn.
    public let text: String
    /// Line timestamp, when parseable.
    public let timestamp: Date?

    /// Creates a parsed transcript turn.
    public init(id: String, role: AgentRoomTranscriptRole, text: String, timestamp: Date?) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Parses Claude Code transcript JSONL files (`~/.claude/projects/<slug>/<session>.jsonl`)
/// into plain conversational turns.
///
/// This is the deterministic wire-time backfill reader: it needs only a file
/// path recorded by the hook session store, no live session bindings, tailers,
/// or in-app registries — the components whose warm-up races previously made
/// backfill silently miss pre-wire messages.
public enum ClaudeTranscriptFileParser {
    /// Maximum bytes read from the end of a transcript file. Transcripts grow
    /// to tens of MB; only the recent tail is relevant for room backfill.
    public static let defaultMaxTailBytes = 512 * 1024

    /// Parses the last `limit` conversational turns from a transcript file.
    ///
    /// Reads at most `maxTailBytes` from the end of the file and drops the
    /// first (possibly truncated) line of the tail window.
    public static func parseTurns(
        fileURL: URL,
        limit: Int,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> [ClaudeTranscriptFileTurn] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let start = fileSize > UInt64(maxTailBytes) ? fileSize - UInt64(maxTailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              var text = String(data: data, encoding: .utf8) else {
            return []
        }
        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            // The tail window almost certainly starts mid-line; drop the fragment.
            text = String(text[text.index(after: firstNewline)...])
        }
        return parseTurns(jsonl: text, limit: limit)
    }

    /// Drops turns older than `cutoff`, so wire-time backfill only shares
    /// recent (pre-wire) context and never resurrects an ancient conversation
    /// that happens to still live in a long-running / reused session's
    /// transcript file.
    ///
    /// A turn's own `timestamp` is authoritative when present; turns without a
    /// parseable timestamp fall back to `fallbackDate` (typically the transcript
    /// file's modification date), so a stale file whose lines lack timestamps is
    /// still excluded when the file itself has not been touched recently.
    public static func recentTurns(
        _ turns: [ClaudeTranscriptFileTurn],
        notOlderThan cutoff: Date,
        fallbackDate: Date
    ) -> [ClaudeTranscriptFileTurn] {
        turns.filter { ($0.timestamp ?? fallbackDate) >= cutoff }
    }

    /// Parses the last `limit` conversational turns from JSONL content.
    ///
    /// Keeps only plain `user`/`assistant` conversation text:
    /// - skips meta lines (`isMeta`) and subagent sidechains (`isSidechain`),
    /// - skips tool_use/tool_result-only content,
    /// - skips slash-command echo lines (`<command-...>` / `<local-command-...>`).
    public static func parseTurns(jsonl: String, limit: Int) -> [ClaudeTranscriptFileTurn] {
        guard limit > 0 else { return [] }
        var turns: [ClaudeTranscriptFileTurn] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line.utf8)
            ) as? [String: Any] else { continue }
            guard let turn = parseTurn(object: object) else { continue }
            turns.append(turn)
        }
        return Array(turns.suffix(limit))
    }

    private static func parseTurn(object: [String: Any]) -> ClaudeTranscriptFileTurn? {
        guard let type = object["type"] as? String else { return nil }
        let role: AgentRoomTranscriptRole
        switch type {
        case "user":
            role = .user
        case "assistant":
            role = .assistant
        default:
            return nil
        }
        if (object["isMeta"] as? Bool) == true { return nil }
        if (object["isSidechain"] as? Bool) == true { return nil }
        guard let message = object["message"] as? [String: Any],
              let text = conversationalText(from: message["content"]),
              !text.isEmpty,
              !isCommandEcho(text) else {
            return nil
        }
        let id = (object["uuid"] as? String) ?? UUID().uuidString
        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)
        return ClaudeTranscriptFileTurn(id: id, role: role, text: text, timestamp: timestamp)
    }

    private static func conversationalText(from content: Any?) -> String? {
        if let string = content as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text",
                  let text = block["text"] as? String else {
                return nil
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: "\n")
    }

    private static func isCommandEcho(_ text: String) -> Bool {
        text.hasPrefix("<command-") || text.hasPrefix("<local-command-")
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }
}
