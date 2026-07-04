import MosaicFoundation
import Foundation

struct MosaicExtensionWorktreeCreationResult: Sendable {
    let worktreePath: String
    let workspaceTitle: String
    /// A convenience command (e.g. a sample dev-server launcher) that should run
    /// inside the new workspace's interactive shell. This is *setup*, never the
    /// workspace's primary process.
    let setupCommand: String
}

/// Arguments for spawning a workspace in a freshly created worktree.
///
/// A workspace closes the moment its main process exits, so the worktree
/// `setupCommand` must be delivered as terminal *input* typed into the
/// interactive login shell — never as the surface's primary process. This type
/// deliberately has **no** primary-command field: the workspace's main process
/// is structurally always the login shell, so the "setup command became the
/// main process and the tab died when it exited" bug cannot be expressed here.
struct MosaicExtensionWorktreeWorkspaceSpawnArgs: Sendable, Equatable {
    let title: String
    let workingDirectory: String
    /// Setup command typed into the interactive shell after spawn (with a
    /// trailing newline so it executes), or `nil` when there is no setup.
    let initialTerminalInput: String?
    let inheritWorkingDirectory: Bool
}

extension MosaicExtensionWorktreeCreationResult {
    /// Builds the workspace spawn arguments for this worktree.
    ///
    /// The returned arguments always leave the workspace's main process as the
    /// login shell and deliver ``setupCommand`` as terminal input.
    func workspaceSpawnArgs() -> MosaicExtensionWorktreeWorkspaceSpawnArgs {
        // Worktree creation already ran as a pre-spawn step, so the setup
        // command is delivered as interactive shell input (with a trailing
        // newline so it executes) rather than as the surface's primary process.
        MosaicExtensionWorktreeWorkspaceSpawnArgs(
            title: workspaceTitle,
            workingDirectory: worktreePath,
            initialTerminalInput: setupCommand.isEmpty ? nil : setupCommand + "\n",
            inheritWorkingDirectory: false
        )
    }
}

final class MosaicExtensionProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func complete(_ status: Int32) {
        let continuation: CheckedContinuation<Int32, Never>?
        lock.lock()
        if let pendingContinuation = self.continuation {
            self.continuation = nil
            continuation = pendingContinuation
        } else {
            self.status = status
            continuation = nil
        }
        lock.unlock()
        continuation?.resume(returning: status)
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            let completedStatus: Int32?
            lock.lock()
            if let status {
                completedStatus = status
            } else {
                self.continuation = continuation
                completedStatus = nil
            }
            lock.unlock()

            if let completedStatus {
                continuation.resume(returning: completedStatus)
            }
        }
    }
}

enum MosaicExtensionWorktreePrototype {
    static func createWorktree(projectRootPath: String) async throws -> MosaicExtensionWorktreeCreationResult {
        try await Task.detached(priority: .userInitiated) {
            let projectRoot = URL(fileURLWithPath: projectRootPath, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try await ensureGitRepository(at: projectRoot)
            try await ensureMosaicWorktreeDirectoryIsLocallyIgnored(projectRoot: projectRoot)

            let branchName = "mosaic-sidebar-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8).lowercased())"
            let worktreeRoot = projectRoot
                .appendingPathComponent(".mosaic", isDirectory: true)
                .appendingPathComponent("worktrees", isDirectory: true)
            try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
            let worktree = worktreeRoot.appendingPathComponent(branchName, isDirectory: true)
            try await run("git", ["-C", projectRoot.path, "worktree", "add", "-b", branchName, worktree.path, "HEAD"])
            try writeSampleDevServerFiles(in: worktree, projectName: projectRoot.lastPathComponent)

            let port = 4_100 + abs(branchName.hashValue % 800)
            let samplePath = shellEscaped(worktree.appendingPathComponent("mosaic-sample-dev", isDirectory: true).path)
            return MosaicExtensionWorktreeCreationResult(
                worktreePath: worktree.path,
                workspaceTitle: branchName,
                setupCommand: "cd \(samplePath) && python3 -m http.server \(port)"
            )
        }.value
    }

    private static func ensureGitRepository(at projectRoot: URL) async throws {
        if (try? await run("git", ["-C", projectRoot.path, "rev-parse", "--is-inside-work-tree"])) != nil {
            return
        }
        throw NSError(
            domain: "MosaicExtensionWorktreePrototype",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Project root is not a git repository."]
        )
    }

    private static func ensureMosaicWorktreeDirectoryIsLocallyIgnored(projectRoot: URL) async throws {
        let output = try await runCapturingOutput("git", ["-C", projectRoot.path, "rev-parse", "--git-path", "info/exclude"])
        guard let rawPath = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            throw NSError(
                domain: "MosaicExtensionWorktreePrototype",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not resolve git exclude file."]
            )
        }

        let excludeURL = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath).standardizedFileURL
            : projectRoot.appendingPathComponent(rawPath).standardizedFileURL
        try FileManager.default.createDirectory(at: excludeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: excludeURL, encoding: .utf8)) ?? ""
        let alreadyIgnored = existing
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0 == ".mosaic" || $0 == ".mosaic/" }
        guard !alreadyIgnored else { return }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let next = existing + separator + "# mosaic extension worktrees\n.mosaic/\n"
        try next.write(to: excludeURL, atomically: true, encoding: .utf8)
    }

    private static func writeSampleDevServerFiles(in worktree: URL, projectName: String) throws {
        let sample = worktree.appendingPathComponent("mosaic-sample-dev", isDirectory: true)
        try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
        let escapedProject = projectName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><title>mosaic worktree</title></head>
          <body style="font: 15px -apple-system; padding: 32px;">
            <h1>\(escapedProject) worktree</h1>
            <p>This page is served from a git worktree created by MosaicExtensionKit.</p>
          </body>
        </html>
        """
        try html.write(to: sample.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws {
        _ = try await runCapturingOutput(executable, arguments)
    }

    private static func runCapturingOutput(_ executable: String, _ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let termination = MosaicExtensionProcessTermination()
        process.terminationHandler = { process in
            termination.complete(process.terminationStatus)
        }
        try process.run()
        let outputCollector = MosaicExtensionPipeOutputCollector(fileHandle: pipe.fileHandleForReading)
        let terminationStatus = await termination.wait()
        let outputData = await outputCollector.finish()
        guard terminationStatus == 0 else {
            let details = String(data: outputData, encoding: .utf8) ?? "command failed"
            throw NSError(
                domain: "MosaicExtensionWorktreePrototype",
                code: Int(terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create worktree.",
                    "MosaicExtensionWorktreePrototypeDetails": details
                ]
            )
        }
        return outputData
    }

    private static func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

final class MosaicExtensionPipeOutputCollector: @unchecked Sendable {
    private struct ReadHandle: @unchecked Sendable {
        let fileHandle: FileHandle
    }

    private let readTask: Task<Data, Never>

    init(fileHandle: FileHandle) {
        let readHandle = ReadHandle(fileHandle: fileHandle)
        readTask = Task.detached(priority: .utility) {
            let data = readHandle.fileHandle.readDataToEndOfFileOrEmpty()
            try? readHandle.fileHandle.close()
            return data
        }
    }

    func finish() async -> Data {
        await readTask.value
    }
}
