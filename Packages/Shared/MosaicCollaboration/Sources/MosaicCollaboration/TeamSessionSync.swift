public import Foundation

/// Pure helpers for the team coding-session sync feature: summarizing a Claude
/// Code transcript into corpus metadata, naming the hidden WIP git ref, and
/// rewriting a pulled transcript for a different local checkout path.
///
/// Networking, git subprocesses, and file placement live in the app layer;
/// everything here is deterministic and unit-testable.
public enum TeamSessionSync {
    /// Hidden git ref that carries the WIP snapshot commit for a session's
    /// uncommitted work (`refs/mosaic/sessions/<sessionId>`).
    public static func wipRefName(sessionId: String) -> String {
        "refs/mosaic/sessions/\(sessionId)"
    }

    /// Branch a teammate lands on when pulling a handed-off session.
    public static func handoffBranchName(sessionId: String) -> String {
        "mosaic/handoff-\(sessionId.prefix(8))"
    }

    /// Claude derives a project directory name from the session's cwd by
    /// replacing both "/" and "." with "-" (e.g. "/Users/x/repo/.claude" ->
    /// "-Users-x-repo--claude"). Mirrors the app's Vault-side encoder; the
    /// pull flow needs it to place a downloaded transcript where
    /// `claude --resume` will look.
    public static func encodeClaudeProjectDir(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

/// Metadata summarized from a Claude Code transcript for the team corpus
/// index: display title, model, and turn count.
public struct TeamSessionTranscriptSummary: Equatable, Sendable {
    public var title: String?
    public var model: String?
    public var turnCount: Int

    public init(title: String? = nil, model: String? = nil, turnCount: Int = 0) {
        self.title = title
        self.model = model
        self.turnCount = turnCount
    }

    private static let maxTitleLength = 120

    /// Summarizes transcript JSONL: the title is the first real user message,
    /// the model is the last assistant `message.model`, and the turn count is
    /// the number of user turns. Lines that fail to parse are skipped, so a
    /// partially-written tail (Claude appends live) never fails the summary.
    public static func summarize(jsonl: String) -> TeamSessionTranscriptSummary {
        var summary = TeamSessionTranscriptSummary()
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let record = object as? [String: Any] else {
                continue
            }
            // Sidechain (subagent) turns describe internal work, not the
            // user's conversation; skip them for title/count purposes.
            if record["isSidechain"] as? Bool == true { continue }
            let type = record["type"] as? String
            if type == "user" {
                summary.turnCount += 1
                if summary.title == nil,
                   let text = userMessageText(record),
                   isDisplayableTitle(text) {
                    summary.title = truncatedTitle(text)
                }
            } else if type == "assistant",
                      let message = record["message"] as? [String: Any],
                      let model = message["model"] as? String,
                      !model.isEmpty {
                summary.model = model
            }
        }
        return summary
    }

    private static func userMessageText(_ record: [String: Any]) -> String? {
        guard let message = record["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let parts = message["content"] as? [[String: Any]] else { return nil }
        let text = parts
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Filters out synthetic user entries (command output, hook results,
    /// interruption markers) that would make a meaningless corpus title.
    private static func isDisplayableTitle(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.hasPrefix("<") { return false }
        if text.hasPrefix("[Request interrupted") { return false }
        if text.hasPrefix("Caveat:") { return false }
        return true
    }

    private static func truncatedTitle(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        guard collapsed.count > maxTitleLength else { return collapsed }
        return String(collapsed.prefix(maxTitleLength)) + "…"
    }
}

/// Rewrites a pulled transcript's recorded cwd paths from the owner's checkout
/// to the local checkout so agents resuming the session see paths that exist.
public enum TeamSessionTranscriptRewriter {
    /// Rewrites every top-level `cwd` field (and `gitBranch`-adjacent path
    /// metadata that equals the remote cwd) in each JSONL line. Lines that are
    /// not valid JSON pass through untouched so an odd tail line never breaks
    /// the transcript. Returns the input unchanged when the paths already
    /// match or either path is empty.
    public static func rewritingCwd(
        jsonl: String,
        from remoteCwd: String,
        to localCwd: String
    ) -> String {
        let remote = remoteCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = localCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty, !local.isEmpty, remote != local else { return jsonl }

        let hadTrailingNewline = jsonl.hasSuffix("\n")
        let rewritten = jsonl
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                rewriteLine(String(line), remote: remote, local: local)
            }
            .joined(separator: "\n")
        if hadTrailingNewline && !rewritten.hasSuffix("\n") {
            return rewritten
        }
        return rewritten
    }

    private static func rewriteLine(_ line: String, remote: String, local: String) -> String {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              var record = object as? [String: Any] else {
            return line
        }
        var changed = false
        if let cwd = record["cwd"] as? String,
           let rewritten = rewrittenPath(cwd, remote: remote, local: local) {
            record["cwd"] = rewritten
            changed = true
        }
        guard changed,
              let encoded = try? JSONSerialization.data(withJSONObject: record),
              let text = String(data: encoded, encoding: .utf8) else {
            return line
        }
        return text
    }

    /// Maps `remote` and paths under `remote/` onto `local`; anything else is
    /// left alone (absolute paths outside the checkout stay meaningful).
    private static func rewrittenPath(_ path: String, remote: String, local: String) -> String? {
        if path == remote { return local }
        if path.hasPrefix(remote + "/") {
            return local + path.dropFirst(remote.count)
        }
        return nil
    }
}
