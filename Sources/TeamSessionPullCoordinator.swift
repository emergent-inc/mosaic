import AppKit
import Foundation
import MosaicCollaboration

/// Deep-link request for pulling a teammate's synced coding session:
/// `mosaic://session/pull?id=<sessionId>[&team=<teamId>]`. Also produced by
/// the `mosaic session pull` CLI command, which opens this URL so both
/// entrypoints share one app-side flow.
struct MosaicSessionPullURLRequest: Equatable {
    /// Session-pull handoff links are always minted server-side as
    /// `mosaic://session/pull?...` (the dashboard "Continue in mosaic" button
    /// and the `mosaic session pull` CLI), so every build — including tagged
    /// debug builds whose callback scheme is `mosaic-dev-<tag>://` — must accept
    /// the stable `mosaic`/`mosaic-nightly`/`mosaic-dev` schemes in addition to
    /// its own callback scheme. Without this, a tagged debug build receives the
    /// `mosaic://` URL (it registered the scheme) but silently rejects it here.
    static var activeSupportedSchemes: Set<String> {
        MosaicSSHURLRequest.activeSupportedSchemes
            .union(MosaicSSHURLRequest.supportedSchemes)
    }

    let sessionId: String
    let teamId: String?

    static func parse(
        _ url: URL,
        supportedSchemes: Set<String> = activeSupportedSchemes
    ) -> MosaicSessionPullURLRequest? {
        guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else {
            return nil
        }
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "session" else { return nil }
        let route = url.path
            .split(separator: "/")
            .map { String($0).lowercased() }
        guard route == ["pull"] else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var sessionId: String?
        var teamId: String?
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "id":
                sessionId = item.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            case "team":
                teamId = item.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                continue
            }
        }
        guard let sessionId, !sessionId.isEmpty, sessionId.count <= 256,
              sessionId.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return MosaicSessionPullURLRequest(
            sessionId: sessionId,
            teamId: (teamId?.isEmpty ?? true) ? nil : teamId
        )
    }

    static func url(sessionId: String, teamId: String?, scheme: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "session"
        components.path = "/pull"
        var queryItems = [URLQueryItem(name: "id", value: sessionId)]
        if let teamId, !teamId.isEmpty {
            queryItems.append(URLQueryItem(name: "team", value: teamId))
        }
        components.queryItems = queryItems
        return components.url
    }
}

/// Pulls a teammate's synced session from the team corpus and continues it
/// locally: downloads metadata + transcript from the collaboration worker,
/// resolves a local checkout of the same repo, fetches the branch and the
/// hidden WIP snapshot ref, places the transcript where `claude --resume`
/// will find it (rewriting recorded cwd paths to the local checkout), and
/// opens a new workspace running `claude --resume <id> --fork-session`.
@MainActor
final class TeamSessionPullCoordinator {
    static let shared = TeamSessionPullCoordinator()

    private var pullInFlight = false

    private struct RemoteSession: Decodable {
        var sessionId: String
        var displayName: String?
        var title: String?
        var cwd: String?
        var repoRemoteUrl: String?
        var gitBranch: String?
        var headSha: String?
        var wipRef: String?
    }

    private struct SessionEnvelope: Decodable {
        var teamId: String?
        var session: RemoteSession
    }

    func pull(request: MosaicSessionPullURLRequest) {
        guard !pullInFlight else { return }
        pullInFlight = true
        Task { [weak self] in
            await self?.performPull(request: request)
            self?.pullInFlight = false
        }
    }

    private func performPull(request: MosaicSessionPullURLRequest) async {
        #if DEBUG
        mosaicDebugLog("teamPull.begin sessionId=\(request.sessionId) team=\(request.teamId ?? "nil")")
        #endif
        guard let coordinator = AppDelegate.shared?.auth?.coordinator,
              let token = try? await coordinator.accessToken() else {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=noToken")
            #endif
            presentFailure(String(
                localized: "teamSessions.pull.error.signedOut",
                defaultValue: "Sign in to mosaic to pull a team session."
            ))
            return
        }

        let envelope: SessionEnvelope
        let transcript: String
        do {
            envelope = try await fetchMetadata(request: request, accessToken: token)
            transcript = try await fetchTranscript(request: request, accessToken: token)
        } catch {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=download error=\(error)")
            #endif
            presentFailure(String(
                localized: "teamSessions.pull.error.download",
                defaultValue: "Could not download the session from your team's corpus."
            ))
            return
        }
        let session = envelope.session
        #if DEBUG
        mosaicDebugLog(
            "teamPull.downloaded sessionId=\(session.sessionId) cwd=\(session.cwd ?? "nil") " +
            "remote=\(session.repoRemoteUrl ?? "nil") branch=\(session.gitBranch ?? "nil") " +
            "transcriptBytes=\(transcript.utf8.count)"
        )
        #endif

        guard let localCwd = await resolveLocalCheckout(session: session) else {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=noLocalCheckout")
            #endif
            return
        }
        #if DEBUG
        mosaicDebugLog("teamPull.checkout localCwd=\(localCwd)")
        #endif

        // Git preparation is best-effort: a failed fetch or dirty tree still
        // leaves a resumable transcript, just without the branch checkout.
        let gitNote = await Task.detached(priority: .userInitiated) {
            Self.prepareCheckout(session: session, localCwd: localCwd)
        }.value

        let placed = await Task.detached(priority: .userInitiated) {
            Self.placeTranscript(session: session, transcript: transcript, localCwd: localCwd)
        }.value
        guard placed else {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=placeTranscript")
            #endif
            presentFailure(String(
                localized: "teamSessions.pull.error.place",
                defaultValue: "Could not write the session transcript for Claude to resume."
            ))
            return
        }
        #if DEBUG
        mosaicDebugLog("teamPull.placedTranscript gitNote=\(gitNote ?? "nil")")
        #endif

        TeamSessionPullMarkerStore.record(marker: .init(
            cwd: localCwd,
            parentSessionId: session.sessionId,
            teamId: envelope.teamId,
            createdAt: Date().timeIntervalSince1970
        ))

        openResumeWorkspace(session: session, localCwd: localCwd)

        if let gitNote {
            presentInfo(gitNote)
        }
    }

    // MARK: - Worker fetches

    private func fetchMetadata(
        request: MosaicSessionPullURLRequest,
        accessToken: String
    ) async throws -> SessionEnvelope {
        let data = try await fetchData(
            path: "v1/sessions/\(request.sessionId)",
            teamId: request.teamId,
            accessToken: accessToken
        )
        return try JSONDecoder().decode(SessionEnvelope.self, from: data)
    }

    private func fetchTranscript(
        request: MosaicSessionPullURLRequest,
        accessToken: String
    ) async throws -> String {
        let data = try await fetchData(
            path: "v1/sessions/\(request.sessionId)/transcript",
            teamId: request.teamId,
            accessToken: accessToken
        )
        guard let transcript = String(data: data, encoding: .utf8), !transcript.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }
        return transcript
    }

    private func fetchData(path: String, teamId: String?, accessToken: String) async throws -> Data {
        var components = URLComponents(
            url: TeamSessionSyncSettings.baseURL().appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if let teamId {
            components?.queryItems = [URLQueryItem(name: "teamId", value: teamId)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Checkout resolution

    /// Prefers the session's own cwd when it is a checkout of the same repo
    /// (same machine or shared path convention), then any open workspace whose
    /// directory is a checkout of the repo, then asks the user to pick one.
    private func resolveLocalCheckout(session: RemoteSession) async -> String? {
        var candidates: [String] = []
        if let cwd = session.cwd, !cwd.isEmpty {
            candidates.append((cwd as NSString).expandingTildeInPath)
        }
        if let tabManagers = AppDelegate.shared?.allTabManagersForSessionPull() {
            for manager in tabManagers {
                for workspace in manager.tabs {
                    let directory = workspace.currentDirectory
                    if !directory.isEmpty {
                        candidates.append((directory as NSString).expandingTildeInPath)
                    }
                }
            }
        }
        let remoteURL = session.repoRemoteUrl
        let resolved = await Task.detached(priority: .userInitiated) {
            Self.matchingCheckout(candidates: candidates, remoteURL: remoteURL)
        }.value
        if let resolved { return resolved }

        return await promptForCheckout(session: session)
    }

    private nonisolated static func matchingCheckout(
        candidates: [String],
        remoteURL: String?
    ) -> String? {
        var seen = Set<String>()
        for candidate in candidates {
            let standardized = (candidate as NSString).standardizingPath
            guard seen.insert(standardized).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard let normalizedRemote = remoteURL.map(normalizedGitRemote) else {
                // No recorded remote: the owner's cwd existing locally is the
                // best available signal.
                return standardized
            }
            guard let state = TeamSessionGit.captureState(cwd: standardized),
                  let candidateRemote = state.remoteURL,
                  normalizedGitRemote(candidateRemote) == normalizedRemote else {
                continue
            }
            return standardized
        }
        return nil
    }

    /// Normalizes git remotes so `git@github.com:acme/app.git`,
    /// `ssh://git@github.com/acme/app`, and `https://github.com/acme/app.git`
    /// all compare equal.
    nonisolated static func normalizedGitRemote(_ remote: String) -> String {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["ssh://git@", "ssh://", "git://", "https://", "http://", "git@"] {
            if value.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        value = value.replacingOccurrences(of: ":", with: "/")
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        return value
    }

    private func promptForCheckout(session: RemoteSession) async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "teamSessions.pull.choosePrompt", defaultValue: "Use Checkout")
        if let remote = session.repoRemoteUrl, !remote.isEmpty {
            panel.message = String(
                localized: "teamSessions.pull.chooseMessage.repo",
                defaultValue: "Choose your local checkout of \(remote) to continue this session in."
            )
        } else {
            panel.message = String(
                localized: "teamSessions.pull.chooseMessage",
                defaultValue: "Choose the project folder to continue this session in."
            )
        }
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - Git preparation

    /// Fetches the session's branch and WIP snapshot ref, then lands a
    /// `mosaic/handoff-<id>` branch on the snapshot (or branch head). Returns
    /// a user-facing note when something needs attention, nil when fully
    /// applied silently.
    private nonisolated static func prepareCheckout(
        session: RemoteSession,
        localCwd: String
    ) -> String? {
        guard TeamSessionGit.captureState(cwd: localCwd) != nil else { return nil }

        var refspecs: [String] = []
        if let branch = session.gitBranch, !branch.isEmpty {
            refspecs.append(branch)
        }
        if let wipRef = session.wipRef, !wipRef.isEmpty {
            refspecs.append("+\(wipRef):\(wipRef)")
        }
        if !refspecs.isEmpty {
            _ = TeamSessionGit.fetch(cwd: localCwd, refspecs: refspecs)
        }

        let targetCommit = resolveTargetCommit(session: session, localCwd: localCwd)
        guard let targetCommit else {
            return String(
                localized: "teamSessions.pull.note.noGitState",
                defaultValue: "The session transcript was pulled, but its git state could not be fetched. Make sure the owner's branch is pushed."
            )
        }

        let handoffBranch = TeamSessionSync.handoffBranchName(sessionId: session.sessionId)
        guard TeamSessionGit.createBranch(cwd: localCwd, name: handoffBranch, at: targetCommit) else {
            return nil
        }
        if TeamSessionGit.isWorkingTreeClean(cwd: localCwd) {
            _ = TeamSessionGit.checkout(cwd: localCwd, branch: handoffBranch)
            return nil
        }
        return String(
            localized: "teamSessions.pull.note.dirtyTree",
            defaultValue: "Branch \(handoffBranch) was created with the session's code state, but your working tree has changes, so it was not checked out automatically."
        )
    }

    private nonisolated static func resolveTargetCommit(
        session: RemoteSession,
        localCwd: String
    ) -> String? {
        if let wipRef = session.wipRef,
           let commit = TeamSessionGit.revParse(cwd: localCwd, ref: wipRef) {
            return commit
        }
        if let headSha = session.headSha,
           let commit = TeamSessionGit.revParse(cwd: localCwd, ref: headSha) {
            return commit
        }
        if let branch = session.gitBranch,
           let commit = TeamSessionGit.revParse(cwd: localCwd, ref: "origin/\(branch)") {
            return commit
        }
        return nil
    }

    // MARK: - Transcript placement

    /// Writes the transcript into the Claude project directory derived from
    /// the local checkout path (that is where `claude --resume` looks),
    /// rewriting the owner's recorded cwd paths to the local checkout.
    private nonisolated static func placeTranscript(
        session: RemoteSession,
        transcript: String,
        localCwd: String
    ) -> Bool {
        let rewritten: String
        if let remoteCwd = session.cwd, !remoteCwd.isEmpty {
            rewritten = TeamSessionTranscriptRewriter.rewritingCwd(
                jsonl: transcript,
                from: remoteCwd,
                to: localCwd
            )
        } else {
            rewritten = transcript
        }
        let projectDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(
                TeamSessionSync.encodeClaudeProjectDir(localCwd),
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            let fileURL = projectDir.appendingPathComponent(
                "\(session.sessionId).jsonl",
                isDirectory: false
            )
            try rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Resume

    private func openResumeWorkspace(session: RemoteSession, localCwd: String) {
        guard let tabManager = AppDelegate.shared?.tabManagerForSessionPull() else {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=noTabManager")
            #endif
            return
        }
        // Fork on resume so the teammate's continuation gets its own session
        // id and never appends under the owner's session.
        let command = AgentResumeCommandBuilder.forkShellCommand(
            kind: .claude,
            sessionId: session.sessionId,
            launchCommand: nil,
            workingDirectory: localCwd
        )
        guard let command else {
            #if DEBUG
            mosaicDebugLog("teamPull.fail reason=noResumeCommand")
            #endif
            return
        }
        #if DEBUG
        mosaicDebugLog("teamPull.openWorkspace cwd=\(localCwd) command=\(command)")
        #endif
        tabManager.addWorkspace(
            title: session.title,
            workingDirectory: localCwd,
            initialTerminalInput: command + "\n"
        )
    }

    // MARK: - Alerts

    private func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "teamSessions.pull.error.title",
            defaultValue: "Could Not Pull Session"
        )
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "teamSessions.pull.info.title",
            defaultValue: "Session Pulled"
        )
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
