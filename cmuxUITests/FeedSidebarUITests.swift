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
        app.launchEnvironment["CMUX_SOCKET_ENABLE"] = "1"
        app.launchEnvironment["CMUX_SOCKET_MODE"] = "allowAll"
        app.launchEnvironment["CMUX_TAG"] = launchTag
        app.launchEnvironment["CMUX_UI_TEST_SOCKET_SANITY"] = "1"
        launchAndAllowBackground(app)

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

        // Reveal the right sidebar and toggle to Feed. Uses accessibility
        // identifiers registered on the ModeBarButton row.
        let feedButton = app.buttons["Feed"].firstMatch
        if !feedButton.waitForExistence(timeout: 5) {
            // Fall back: send the right-sidebar toggle shortcut (⌘⌥B).
            app.typeKey("b", modifierFlags: [.command, .option])
            _ = feedButton.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(feedButton.exists, "Feed tab not visible in right sidebar")
        feedButton.click()

        // Push a synthetic permission request via the socket.
        let requestId = "uitest-\(UUID().uuidString)"
        let replyPayload = try sendFeedPush(requestId: requestId, waitSeconds: 30)

        // The reply arrives once the Feed row's Allow Once button is
        // clicked — run that on the UI side while the send is in-flight.
        guard let allowButton = waitForFirstButton(
            app,
            identifiers: ["FeedPermissionAllowOnceButton", "Allow Once", "Once"],
            timeout: 10
        ) else {
            XCTFail("Allow Once button did not appear in Feed. socket outcome: \(replyPayload.immediateDescription())")
            return
        }
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

    private func launchAndAllowBackground(_ app: XCUIApplication) {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("App activation may fail on headless CI runners", options: options) {
            app.launch()
        }

        if app.state == .runningForeground || app.state == .runningBackground {
            return
        }
        XCTFail("cmux failed to launch for Feed UI test. state=\(app.state.rawValue)")
    }

    private func waitForFirstButton(
        _ app: XCUIApplication,
        identifiers: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers {
                let button = app.buttons[identifier].firstMatch
                if button.exists {
                    return button
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private struct FeedPushResult {
        let status: String
        let mode: String
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

        func immediateDescription() -> String {
            do {
                let result = try result(timeout: 0.5)
                return "status=\(result.status) mode=\(result.mode)"
            } catch {
                return String(describing: error)
            }
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
                let frame: [String: Any] = [
                    "id": UUID().uuidString,
                    "method": "feed.push",
                    "params": params,
                ]
                let data = try JSONSerialization.data(withJSONObject: frame)
                let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"
                let response = try self.sendLine(line)
                guard let respData = response.data(using: .utf8),
                      let respObj = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                      (respObj["ok"] as? Bool) == true,
                      let result = respObj["result"] as? [String: Any],
                      let status = result["status"] as? String
                else {
                    future.resolve(.failure(NSError(
                        domain: "FeedPush", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "invalid response: \(response)"]
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

    private func sendLine(_ line: String) throws -> String {
        do {
            return try sendLineViaDarwinSocket(line)
        } catch {
            if let response = sendLineViaNetcat(line) {
                return response
            }
            throw error
        }
    }

    private func sendLineViaDarwinSocket(_ line: String) throws -> String {
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
        memset(&addr, 0, MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketPath.utf8CString)
        guard bytes.count <= maxLen else {
            throw NSError(
                domain: "FeedSidebarUITests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "socket path too long: \(socketPath)"]
            )
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            memset(raw, 0, maxLen)
            for index in 0..<bytes.count {
                raw[index] = bytes[index]
            }
        }

        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
        let size = socklen_t(pathOffset + bytes.count)
#if os(macOS)
        addr.sun_len = UInt8(min(Int(size), 255))
#endif
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

    private func sendLineViaNetcat(_ line: String) -> String? {
        let nc = "/usr/bin/nc"
        guard FileManager.default.isExecutableFile(atPath: nc) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nc)
        proc.arguments = ["-U", socketPath, "-w", "3"]

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        if let data = line.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()
        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let outStr = String(data: outData, encoding: .utf8) else { return nil }
        if let first = outStr.split(separator: "\n", maxSplits: 1).first {
            return String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = outStr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func removeSocketFile() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}
