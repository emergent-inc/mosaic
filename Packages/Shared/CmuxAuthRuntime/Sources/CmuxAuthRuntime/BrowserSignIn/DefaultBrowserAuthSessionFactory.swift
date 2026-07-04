#if os(macOS)
public import AppKit
public import Foundation
@preconcurrency import Network

/// Opens hosted sign-in in the user's default browser with a localhost callback.
@MainActor
public final class DefaultBrowserAuthSessionFactory: HostBrowserAuthSessionFactory {
    private let openURL: @MainActor (URL) -> Bool
    private let activateApp: @MainActor () -> Void
    private let log = AuthDebugLog()

    /// Creates a factory that opens sign-in URLs in the system default browser.
    /// - Parameters:
    ///   - openURL: Opens the rewritten sign-in URL; tests inject a recorder.
    ///   - activateApp: Brings the app forward after the loopback callback.
    public init(
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        activateApp: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        self.openURL = openURL
        self.activateApp = activateApp
    }

    public func makeSession(
        signInURL: URL,
        callbackScheme: String,
        completion: @escaping @MainActor (HostBrowserAuthSessionResult) -> Void
    ) -> any HostBrowserAuthSession {
        log.log("auth.defaultBrowser.makeSession signInURL=\(signInURL.absoluteString) callbackScheme=\(callbackScheme)")
        return DefaultBrowserAuthSession(
            signInURL: signInURL,
            callbackScheme: callbackScheme,
            openURL: openURL,
            activateApp: activateApp,
            completion: completion,
            log: log
        )
    }
}

@MainActor
private final class DefaultBrowserAuthSession: HostBrowserAuthSession {
    private let signInURL: URL
    private let callbackScheme: String
    private let openURL: @MainActor (URL) -> Bool
    private let activateApp: @MainActor () -> Void
    private let completion: @MainActor (HostBrowserAuthSessionResult) -> Void
    private let log: AuthDebugLog
    private let queue = DispatchQueue(label: "com.cmux.auth.loopback")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var completed = false
    private var openedBrowser = false

    init(
        signInURL: URL,
        callbackScheme: String,
        openURL: @escaping @MainActor (URL) -> Bool,
        activateApp: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor (HostBrowserAuthSessionResult) -> Void,
        log: AuthDebugLog
    ) {
        self.signInURL = signInURL
        self.callbackScheme = callbackScheme
        self.openURL = openURL
        self.activateApp = activateApp
        self.completion = completion
        self.log = log
    }

    func start() -> Bool {
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
            log.log("auth.defaultBrowser.loopback.start")
            return true
        } catch {
            log.log("auth.defaultBrowser.loopback.startFailed \(error)")
            return false
        }
    }

    func cancel() {
        complete(.cancelled(reason: "cancelled"))
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard !openedBrowser else { return }
            guard let port = listener?.port else {
                complete(.failed(reason: "loopback_missing_port"))
                return
            }
            let url = signInURLForLoopback(port: port)
            openedBrowser = true
            let opened = openURL(url)
            log.log("auth.defaultBrowser.start opened=\(opened)")
            if !opened {
                complete(.failed(reason: "open_default_browser_failed"))
            }
        case .failed:
            complete(.failed(reason: "loopback_listener_failed"))
        case .cancelled:
            if !completed {
                complete(.cancelled(reason: "loopback_listener_cancelled"))
            }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !completed, self.connection == nil else {
            connection.cancel()
            return
        }
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    self?.complete(.failed(reason: "loopback_connection_failed"))
                }
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            Task { @MainActor in
                self?.handleRequestData(data, on: connection)
            }
        }
    }

    private func handleRequestData(_ data: Data?, on connection: NWConnection) {
        guard !completed,
              let data,
              let request = String(data: data, encoding: .utf8),
              let callbackURL = callbackURL(fromHTTPRequest: request) else {
            sendResponse(status: "400 Bad Request", on: connection)
            complete(.failed(reason: "loopback_invalid_request"))
            return
        }

        sendResponse(status: "200 OK", on: connection)
        activateApp()
        complete(.callback(callbackURL))
    }

    private func sendResponse(status: String, on connection: NWConnection) {
        let body = status.hasPrefix("200") ? callbackCompletionHTML() : ""
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Cache-Control: no-store\r
        Connection: close\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func callbackCompletionHTML() -> String {
        DefaultBrowserAuthCallbackPage(
            title: String(
                localized: "auth.loopback_callback.title",
                defaultValue: "Mosaic opened, you may close this tab",
                bundle: .main
            )
        )
        .html()
    }

    private func complete(_ result: HostBrowserAuthSessionResult) {
        guard !completed else { return }
        completed = true
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        log.log("auth.defaultBrowser.complete \(sessionResultSummary(result))")
        completion(result)
    }

    private func signInURLForLoopback(port: NWEndpoint.Port) -> URL {
        guard var signInComponents = URLComponents(url: signInURL, resolvingAgainstBaseURL: false),
              var signInItems = signInComponents.queryItems,
              let afterAuthIndex = signInItems.firstIndex(where: { $0.name == "after_auth_return_to" }),
              let afterAuthValue = signInItems[afterAuthIndex].value,
              var afterAuthComponents = URLComponents(string: afterAuthValue) else {
            return signInURL
        }

        var loopbackComponents = URLComponents()
        loopbackComponents.scheme = "http"
        loopbackComponents.host = "127.0.0.1"
        loopbackComponents.port = Int(port.rawValue)
        loopbackComponents.path = "/auth-callback"
        if let state = callbackState(from: afterAuthComponents) {
            loopbackComponents.queryItems = [
                URLQueryItem(name: "mosaic_auth_state", value: state),
            ]
        }
        guard let loopbackURL = loopbackComponents.url else {
            return signInURL
        }

        var afterAuthItems = afterAuthComponents.queryItems ?? []
        if let nativeReturnIndex = afterAuthItems.firstIndex(where: { $0.name == "native_app_return_to" }) {
            afterAuthItems[nativeReturnIndex] = URLQueryItem(
                name: "native_app_return_to",
                value: loopbackURL.absoluteString
            )
        } else {
            afterAuthItems.append(URLQueryItem(name: "native_app_return_to", value: loopbackURL.absoluteString))
        }
        afterAuthComponents.queryItems = afterAuthItems
        guard let afterAuthURL = afterAuthComponents.url else {
            return signInURL
        }

        signInItems[afterAuthIndex] = URLQueryItem(
            name: "after_auth_return_to",
            value: afterAuthURL.absoluteString
        )
        signInComponents.queryItems = signInItems
        return signInComponents.url ?? signInURL
    }

    private func callbackState(from afterAuthComponents: URLComponents) -> String? {
        guard let nativeReturnTo = afterAuthComponents.queryItems?
            .first(where: { $0.name == "native_app_return_to" })?
            .value,
            let nativeComponents = URLComponents(string: nativeReturnTo) else {
            return nil
        }
        return nativeComponents.queryItems?
            .first(where: { $0.name == "mosaic_auth_state" })?
            .value
    }

    private func callbackURL(fromHTTPRequest request: String) -> URL? {
        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "GET",
              let loopbackURL = URL(string: String(parts[1]), relativeTo: URL(string: "http://127.0.0.1")),
              let components = URLComponents(url: loopbackURL, resolvingAgainstBaseURL: true),
              components.path == "/auth-callback" else {
            return nil
        }

        var callbackComponents = URLComponents()
        callbackComponents.scheme = callbackScheme
        callbackComponents.host = "auth-callback"
        callbackComponents.percentEncodedQuery = components.percentEncodedQuery
        return callbackComponents.url
    }

    private func sessionResultSummary(_ result: HostBrowserAuthSessionResult) -> String {
        switch result {
        case let .callback(url):
            return "result=callback scheme=\(url.scheme ?? "nil")"
        case let .cancelled(reason):
            return "result=cancelled reason=\(reason)"
        case let .failed(reason):
            return "result=failed reason=\(reason)"
        }
    }
}
#endif
