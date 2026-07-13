import Foundation
import MosaicCollaboration

/// Team session sync settings and endpoint resolution.
nonisolated enum TeamSessionSyncSettings {
    /// Mirrors `SettingCatalog().automation.teamSessionSync.userDefaultsKey`.
    static let enabledKey = "teamSessionSyncEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: enabledKey) != nil else { return false }
        return defaults.bool(forKey: enabledKey)
    }

    /// The collaboration worker hosts the team session corpus alongside the
    /// live relay; same base URL as `CollaborationRuntime`'s default relay.
    static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["MOSAIC_TEAM_SESSION_SYNC_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://mosaic-collaboration-worker.dorsa-rohani.workers.dev")!
    }
}

/// Handoff lineage markers written by the pull flow and claimed by the sync
/// service: when a pulled session is forked locally, the fork is a brand-new
/// session id, so the pull flow records "a fork of <parent> is about to start
/// in <cwd>" and the first sync of a new session in that cwd attaches the
/// parent id. Stored in `~/.mosaicterm` beside the hook stores.
nonisolated enum TeamSessionPullMarkerStore {
    struct Marker: Codable {
        var cwd: String
        var parentSessionId: String
        var teamId: String?
        var createdAt: TimeInterval
    }

    private static let maxMarkerAge: TimeInterval = 30 * 60

    static func fileURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".mosaicterm", isDirectory: true)
            .appendingPathComponent("team-session-pull-markers.json", isDirectory: false)
    }

    static func record(marker: Marker, homeDirectory: String = NSHomeDirectory()) {
        var markers = load(homeDirectory: homeDirectory)
        markers.append(marker)
        save(markers, homeDirectory: homeDirectory)
    }

    /// Removes and returns the parent session id for a fresh session in `cwd`,
    /// when a recent marker matches and the session started after the marker.
    static func claimParentSessionId(
        cwd: String?,
        sessionStartedAt: TimeInterval,
        homeDirectory: String = NSHomeDirectory(),
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let standardized = (cwd as NSString).standardizingPath
        var markers = load(homeDirectory: homeDirectory)
        guard let index = markers.firstIndex(where: { marker in
            (marker.cwd as NSString).standardizingPath == standardized
                && now - marker.createdAt < maxMarkerAge
                && sessionStartedAt >= marker.createdAt - 5
        }) else {
            return nil
        }
        let parent = markers.remove(at: index).parentSessionId
        save(markers, homeDirectory: homeDirectory)
        return parent
    }

    private static func load(homeDirectory: String) -> [Marker] {
        guard let data = try? Data(contentsOf: fileURL(homeDirectory: homeDirectory)),
              let markers = try? JSONDecoder().decode([Marker].self, from: data) else {
            return []
        }
        let now = Date().timeIntervalSince1970
        return markers.filter { now - $0.createdAt < maxMarkerAge }
    }

    private static func save(_ markers: [Marker], homeDirectory: String) {
        let url = fileURL(homeDirectory: homeDirectory)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(markers) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Uploads each opted-in Claude Code session to the team's shared corpus at
/// turn boundaries so teammates can pull and continue it.
///
/// Trigger: a directory watcher on `~/.mosaicterm` (the hook stores that
/// `mosaic hooks claude stop` / `prompt-submit` rewrite at every turn
/// boundary), debounced a couple of seconds. Each pass diffs the Claude hook
/// store's per-session `updatedAt` stamps against what was already uploaded
/// and syncs only changed sessions, so the watcher's granularity is exactly
/// "one upload per finished agent turn".
///
/// The first pass after launch only records baseline stamps — enabling the
/// feature never bulk-uploads historical sessions, only ones that take a turn
/// while the app is running.
@MainActor
final class TeamSessionSyncService {
    static let shared = TeamSessionSyncService()

    private var directoryWatchSource: (any DispatchSourceFileSystemObject)?
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var passPending = false
    private var hasBaseline = false
    private var uploadedStampsBySessionId: [String: TimeInterval] = [:]
    private var pushedWipTreeBySessionId: [String: String] = [:]

    private struct HookSessionRecord: Codable {
        var sessionId: String
        var cwd: String?
        var transcriptPath: String?
        var updatedAt: TimeInterval
    }

    private struct HookSessionStoreFile: Codable {
        var sessions: [String: HookSessionRecord] = [:]
    }

    func start() {
        guard directoryWatchSource == nil else { return }
        let directoryURL = RestorableAgentKind.claude
            .hookStoreFileURL()
            .deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleSyncPass()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directoryWatchSource = source
        // Establish the baseline immediately so the first real turn after
        // launch is recognized as a change.
        scheduleSyncPass()
    }

    private func scheduleSyncPass() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.runSyncPass()
        }
    }

    private func runSyncPass() {
        if syncTask != nil {
            passPending = true
            return
        }
        syncTask = Task { [weak self] in
            await self?.syncPass()
            guard let self else { return }
            self.syncTask = nil
            if self.passPending {
                self.passPending = false
                self.scheduleSyncPass()
            }
        }
    }

    private func syncPass() async {
        let storeURL = RestorableAgentKind.claude.hookStoreFileURL()
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(HookSessionStoreFile.self, from: data) else {
            return
        }
        var recordsBySessionId: [String: HookSessionRecord] = [:]
        for record in store.sessions.values {
            let sessionId = record.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionId.isEmpty, record.transcriptPath != nil else { continue }
            if let existing = recordsBySessionId[sessionId], existing.updatedAt >= record.updatedAt {
                continue
            }
            recordsBySessionId[sessionId] = record
        }

        guard hasBaseline else {
            // First observation after launch: remember what already exists so
            // only sessions that take a turn from now on are uploaded.
            for (sessionId, record) in recordsBySessionId {
                uploadedStampsBySessionId[sessionId] = record.updatedAt
            }
            hasBaseline = true
            return
        }

        guard TeamSessionSyncSettings.isEnabled() else {
            #if DEBUG
            mosaicDebugLog("teamSync.skip reason=disabled")
            #endif
            return
        }
        guard let coordinator = AppDelegate.shared?.auth?.coordinator,
              let token = try? await coordinator.accessToken() else {
            #if DEBUG
            mosaicDebugLog("teamSync.skip reason=noToken")
            #endif
            return
        }

        let changed = recordsBySessionId.filter { $0.value.updatedAt > (uploadedStampsBySessionId[$0.key] ?? 0) }
        #if DEBUG
        mosaicDebugLog("teamSync.pass changed=\(changed.count) total=\(recordsBySessionId.count) host=\(TeamSessionSyncSettings.baseURL().host ?? "?")")
        #endif

        for (sessionId, record) in recordsBySessionId {
            let uploaded = uploadedStampsBySessionId[sessionId]
            guard record.updatedAt > (uploaded ?? 0) else { continue }
            let isFirstUpload = uploaded == nil
            let lastPushedTree = pushedWipTreeBySessionId[sessionId]
            // Optimistically stamp before the upload so a failing session is
            // retried on its next turn rather than in a tight loop.
            uploadedStampsBySessionId[sessionId] = record.updatedAt
            let outcome = await Task.detached(priority: .utility) {
                await Self.uploadSession(
                    record: record,
                    sessionId: sessionId,
                    isFirstUpload: isFirstUpload,
                    lastPushedTree: lastPushedTree,
                    accessToken: token
                )
            }.value
            if let pushedTree = outcome?.pushedTree {
                pushedWipTreeBySessionId[sessionId] = pushedTree
            }
        }
    }

    private struct UploadOutcome {
        var pushedTree: String?
    }

    /// Reads the transcript, captures git state (pushing a WIP snapshot ref
    /// when the tree is dirty), and posts the session to the worker. Runs off
    /// the main actor; failures are silent and retried on the next turn.
    private nonisolated static func uploadSession(
        record: HookSessionRecord,
        sessionId: String,
        isFirstUpload: Bool,
        lastPushedTree: String?,
        accessToken: String
    ) async -> UploadOutcome? {
        guard let transcriptPath = record.transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcriptPath.isEmpty else {
            return nil
        }
        let expandedPath = (transcriptPath as NSString).expandingTildeInPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: expandedPath),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= 24 * 1024 * 1024,
              let transcriptData = FileManager.default.contents(atPath: expandedPath),
              let transcript = String(data: transcriptData, encoding: .utf8) else {
            return nil
        }

        let summary = TeamSessionTranscriptSummary.summarize(jsonl: transcript)
        var session: [String: Any] = [
            "sessionId": sessionId,
            "agent": "claude",
        ]
        if let title = summary.title { session["title"] = title }
        if let model = summary.model { session["model"] = model }
        session["turnCount"] = summary.turnCount
        if let cwd = record.cwd, !cwd.isEmpty { session["cwd"] = cwd }

        var outcome = UploadOutcome()
        if let cwd = record.cwd, let git = TeamSessionGit.captureState(cwd: cwd) {
            if let remote = git.remoteURL { session["repoRemoteUrl"] = remote }
            if let branch = git.branch { session["gitBranch"] = branch }
            if let head = git.headSha { session["headSha"] = head }
            if let dirtyTree = git.dirtyWorkingTree {
                if dirtyTree == lastPushedTree {
                    // Same dirty state already pushed; the existing ref is
                    // current, and omitting wipRef keeps the recorded value.
                    outcome.pushedTree = dirtyTree
                } else if TeamSessionGit.pushWipSnapshot(
                    cwd: cwd,
                    sessionId: sessionId,
                    treeHash: dirtyTree,
                    headSha: git.headSha
                ) {
                    session["wipRef"] = TeamSessionSync.wipRefName(sessionId: sessionId)
                    outcome.pushedTree = dirtyTree
                }
            } else {
                // Clean tree: explicitly clear any previously recorded WIP ref.
                session["wipRef"] = NSNull()
            }
        }

        if isFirstUpload {
            let createdAt = ((try? FileManager.default.attributesOfItem(atPath: expandedPath))?[.creationDate] as? Date)?
                .timeIntervalSince1970 ?? record.updatedAt
            if let parent = TeamSessionPullMarkerStore.claimParentSessionId(
                cwd: record.cwd,
                sessionStartedAt: createdAt
            ) {
                session["parentSessionId"] = parent
            }
        }

        let body: [String: Any] = [
            "session": session,
            "transcript": transcript,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return outcome }

        var request = URLRequest(
            url: TeamSessionSyncSettings.baseURL().appendingPathComponent("v1/sessions/sync")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            #if DEBUG
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            mosaicDebugLog("teamSync.upload sessionId=\(sessionId) status=\(status) bytes=\(payload.count)")
            #endif
        } catch {
            #if DEBUG
            mosaicDebugLog("teamSync.upload sessionId=\(sessionId) error=\(error)")
            #endif
        }
        return outcome
    }
}

/// Git subprocess helpers for team session sync. All calls disable interactive
/// credential prompts and are best-effort: a repo without a remote, a failed
/// push, or a non-git cwd simply degrades to metadata-only sync.
nonisolated enum TeamSessionGit {
    struct State {
        var remoteURL: String?
        var branch: String?
        var headSha: String?
        /// Tree hash of the dirty working tree (nil when clean). Snapshotted
        /// through a temporary index so the user's real index is untouched.
        var dirtyWorkingTree: String?
    }

    static func captureState(cwd: String) -> State? {
        guard runGit(["rev-parse", "--is-inside-work-tree"], cwd: cwd)?.output == "true" else {
            return nil
        }
        var state = State()
        state.remoteURL = runGit(["remote", "get-url", "origin"], cwd: cwd)?.output
        if state.remoteURL == nil,
           let firstRemote = runGit(["remote"], cwd: cwd)?.output.split(separator: "\n").first {
            state.remoteURL = runGit(["remote", "get-url", String(firstRemote)], cwd: cwd)?.output
        }
        if let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)?.output,
           !branch.isEmpty, branch != "HEAD" {
            state.branch = branch
        }
        state.headSha = runGit(["rev-parse", "HEAD"], cwd: cwd)?.output
        let porcelain = runGit(["status", "--porcelain"], cwd: cwd)?.output ?? ""
        if !porcelain.isEmpty {
            state.dirtyWorkingTree = dirtyWorkingTreeHash(cwd: cwd)
        }
        return state
    }

    /// Writes the dirty working tree to a tree object via a throwaway index
    /// (`GIT_INDEX_FILE`), so the user's staged/unstaged split is preserved.
    private static func dirtyWorkingTreeHash(cwd: String) -> String? {
        let tempIndex = FileManager.default.temporaryDirectory
            .appendingPathComponent("mosaic-session-index-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: tempIndex) }
        let environment = ["GIT_INDEX_FILE": tempIndex]
        guard runGit(["read-tree", "HEAD"], cwd: cwd, environment: environment) != nil,
              runGit(["add", "-A", "."], cwd: cwd, environment: environment) != nil,
              let tree = runGit(["write-tree"], cwd: cwd, environment: environment)?.output,
              !tree.isEmpty else {
            return nil
        }
        return tree
    }

    static func fetch(cwd: String, refspecs: [String]) -> Bool {
        runGit(["fetch", "origin"] + refspecs, cwd: cwd, timeout: 60) != nil
    }

    static func revParse(cwd: String, ref: String) -> String? {
        guard let output = runGit(["rev-parse", "--verify", "\(ref)^{commit}"], cwd: cwd)?.output,
              !output.isEmpty else {
            return nil
        }
        return output
    }

    static func createBranch(cwd: String, name: String, at commit: String) -> Bool {
        runGit(["branch", "--force", name, commit], cwd: cwd) != nil
    }

    static func checkout(cwd: String, branch: String) -> Bool {
        runGit(["checkout", branch], cwd: cwd, timeout: 60) != nil
    }

    static func isWorkingTreeClean(cwd: String) -> Bool {
        runGit(["status", "--porcelain"], cwd: cwd)?.output.isEmpty == true
    }

    /// Commits `treeHash` (parented on HEAD) and force-pushes it to the
    /// session's hidden ref. Returns whether the push succeeded.
    static func pushWipSnapshot(cwd: String, sessionId: String, treeHash: String, headSha: String?) -> Bool {
        var commitArgs = ["commit-tree", treeHash, "-m", "mosaic team session snapshot \(sessionId)"]
        if let headSha, !headSha.isEmpty {
            commitArgs.insert(contentsOf: ["-p", headSha], at: 2)
        }
        guard let commit = runGit(commitArgs, cwd: cwd)?.output, !commit.isEmpty else { return false }
        let refName = TeamSessionSync.wipRefName(sessionId: sessionId)
        return runGit(
            ["push", "--force", "origin", "\(commit):\(refName)"],
            cwd: cwd,
            timeout: 60
        ) != nil
    }

    private struct GitResult {
        var output: String
    }

    private static func runGit(
        _ arguments: [String],
        cwd: String,
        environment: [String: String] = [:],
        timeout: TimeInterval = 15
    ) -> GitResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["GIT_TERMINAL_PROMPT"] = "0"
        mergedEnvironment["GIT_OPTIONAL_LOCKS"] = "0"
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stdout concurrently so a command whose output exceeds the pipe
        // buffer can never deadlock against the exit poll below.
        let outputBox = OutputBox()
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.set(stdout.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        _ = drainGroup.wait(timeout: .now() + 2)
        let output = String(data: outputBox.get(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitResult(output: output)
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ newValue: Data) {
            lock.lock()
            data = newValue
            lock.unlock()
        }

        func get() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
