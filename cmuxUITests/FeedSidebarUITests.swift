import Foundation
import XCTest

/// Exercises the right-sidebar Feed end-to-end: boot the app with a
/// dedicated socket, inject a synthetic permission request over the
/// socket's `feed.push` V2 verb, toggle the sidebar to Feed mode, tap
/// Allow Once, and assert the hook-side socket response carries the
/// resolved decision.
final class FeedSidebarUITests: XCTestCase {
    private var socketPath = ""
    private let modeKey = "socketControlMode"
    private let launchTag = "ui-tests-feed-sidebar"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        socketPath = "/tmp/cmux-debug-\(UUID().uuidString).sock"
        removeSocketFile()
    }

    func testFeedReceivesAndResolvesPermissionRequest() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-\(modeKey)", "allowAll"]
        app.launchEnvironment["CMUX_SOCKET_PATH"] = socketPath
        app.launchEnvironment["CMUX_ALLOW_SOCKET_OVERRIDE"] = "1"
        app.launchEnvironment["CMUX_TAG"] = launchTag
        app.launchEnvironment["CMUX_UI_TEST_SOCKET_SANITY"] = "1"
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "cmux failed to launch for Feed UI test"
        )

        // Wait for the socket to come up.
        let socketExists = expectation(description: "socket exists")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: self.socketPath) {
                    socketExists.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        wait(for: [socketExists], timeout: 12)

        // Reveal the right sidebar and toggle to Feed.
        var feedButton = waitForButton(
            in: app,
            matching: ["RightSidebarModeButton.feed", "Feed"],
            timeout: 5
        )
        if feedButton == nil {
            // Fall back: send the right-sidebar toggle shortcut (⌘⌥B).
            app.typeKey("b", modifierFlags: [.command, .option])
            feedButton = waitForButton(
                in: app,
                matching: ["RightSidebarModeButton.feed", "Feed"],
                timeout: 5
            )
        }
        let visibleFeedButton = try XCTUnwrap(
            feedButton,
            "Feed tab not visible in right sidebar"
        )
        visibleFeedButton.click()

        // Push a synthetic permission request via the socket.
        let requestId = "uitest-\(UUID().uuidString)"
        let workstreamId = "uitest-\(requestId)"
        let replyPayload = try sendFeedPush(requestId: requestId, waitSeconds: 30)
        XCTAssertTrue(
            try waitForPendingFeedPermission(workstreamId: workstreamId, timeout: 10),
            "feed.push did not register a pending permission item"
        )

        // The reply arrives once the Feed row's Allow Once button is
        // clicked, run that on the UI side while the send is in-flight.
        let allowButton = try XCTUnwrap(
            waitForButton(
                in: app,
                matching: ["FeedPermissionAllowOnceButton", "Allow Once"],
                timeout: 10
            ),
            "Allow Once button did not appear in Feed"
        )
        allowButton.click()

        // Await the socket reply from the earlier push.
        let result = try replyPayload.result(timeout: 30)
        XCTAssertEqual(
            result.status, "resolved",
            "Expected feed.push to resolve, got status=\(result.status)"
        )
        XCTAssertEqual(result.mode, "once")

        app.terminate()
    }

    // MARK: - Socket helpers

    private struct FeedPushResult {
        let status: String
        let mode: String
    }

    private struct FeedListResult {
        let items: [[String: Any]]
        let rawResponse: String
    }

    private final class FeedPushFuture {
        private let semaphore = DispatchSemaphore(value: 0)
        private var outcome: Result<FeedPushResult, Error>?

        func resolve(_ outcome: Result<FeedPushResult, Error>) {
            self.outcome = outcome
            semaphore.signal()
        }

        func result(timeout: TimeInterval) throws -> FeedPushResult {
            let deadline: DispatchTime = .now() + timeout
            if semaphore.wait(timeout: deadline) == .timedOut {
                throw NSError(domain: "FeedPush", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "feed.push never returned"])
            }
            return try outcome!.get()
        }
    }

    private func sendFeedPush(requestId: String, waitSeconds: Double) throws -> FeedPushFuture {
        let future = FeedPushFuture()
        DispatchQueue.global().async {
            do {
                let params: [String: Any] = [
                    "event": [
                        "session_id": "uitest-\(requestId)",
                        "hook_event_name": "PermissionRequest",
                        "_source": "claude",
                        "tool_name": "Write",
                        "tool_input": ["file_path": "/tmp/feeduitest"],
                        "_opencode_request_id": requestId,
                    ],
                    "wait_timeout_seconds": waitSeconds,
                ]
                let respObj = try self.sendFrame(method: "feed.push", params: params)
                guard (respObj["ok"] as? Bool) == true,
                      let result = respObj["result"] as? [String: Any],
                      let status = result["status"] as? String
                else {
                    future.resolve(.failure(NSError(
                        domain: "FeedPush", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "invalid response: \(respObj)"]
                    )))
                    return
                }
                let mode = (result["decision"] as? [String: Any])?["mode"] as? String ?? ""
                future.resolve(.success(FeedPushResult(status: status, mode: mode)))
            } catch {
                future.resolve(.failure(error))
            }
        }
        return future
    }

    private func waitForButton(
        in app: XCUIApplication,
        matching identifiersOrLabels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifierOrLabel in identifiersOrLabels {
                let candidate = app.buttons[identifierOrLabel].firstMatch
                if candidate.exists {
                    return candidate
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private func waitForPendingFeedPermission(
        workstreamId: String,
        timeout: TimeInterval
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastResponse = ""
        while Date() < deadline {
            let response = try sendFeedList(pendingOnly: true)
            lastResponse = response.rawResponse
            if response.items.contains(where: { item in
                (item["workstream_id"] as? String) == workstreamId
                    && (item["kind"] as? String) == "permissionRequest"
                    && (item["status"] as? String) == "pending"
            }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTContext.runActivity(named: "Last feed.list response") { activity in
            activity.add(XCTAttachment(string: lastResponse))
        }
        return false
    }

    private func sendFeedList(pendingOnly: Bool) throws -> FeedListResult {
        let response = try sendFrame(
            method: "feed.list",
            params: ["pending_only": pendingOnly]
        )
        guard (response["ok"] as? Bool) == true,
              let result = response["result"] as? [String: Any],
              let items = result["items"] as? [[String: Any]]
        else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "invalid feed.list response: \(response)"]
            )
        }
        return FeedListResult(items: items, rawResponse: "\(response)")
    }

    private func sendFrame(method: String, params: [String: Any]) throws -> [String: Any] {
        let frame: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: frame)
        let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        let response = try sendLine(line)
        guard let respData = response.data(using: .utf8),
              let respObj = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "invalid socket response: \(response)"]
            )
        }
        return respObj
    }

    private func sendLine(_ line: String) throws -> String {
        let sockFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockFd != -1 else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "socket() failed errno=\(errno)"]
            )
        }
        defer { close(sockFd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { dst in
                strlcpy(dst.baseAddress!.assumingMemoryBound(to: Int8.self), src, dst.count)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { base in
                connect(sockFd, base, size)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "connect() failed errno=\(errno)"]
            )
        }

        let data = line.data(using: .utf8)!
        _ = data.withUnsafeBytes { bytes in
            send(sockFd, bytes.baseAddress, data.count, 0)
        }

        // Read until newline or EOF.
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(sockFd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            if chunk.prefix(n).contains(0x0A) { break }
        }
        return String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func removeSocketFile() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}
