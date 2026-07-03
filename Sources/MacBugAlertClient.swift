import Foundation

/// Sends high-signal bug summaries to the web bug-alert endpoint.
actor MacBugAlertClient {
    private let endpoint: URL
    private let session: URLSession
    private let isEnabled: @Sendable () -> Bool
    private let sharedSecret: String?

    init(
        endpoint: URL = MacBugAlertClient.defaultEndpoint(),
        session: URLSession = .shared,
        sharedSecret: String? = MacBugAlertClient.defaultSharedSecret(),
        isEnabled: @escaping @Sendable () -> Bool = {
            guard TelemetrySettings.enabledForCurrentLaunch else { return false }
            #if DEBUG
            return ProcessInfo.processInfo.environment["CMUX_BUG_ALERTS_ENABLE"] == "1"
            #else
            return true
            #endif
        }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.sharedSecret = sharedSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isEnabled = isEnabled
    }

    func send(
        event: MacAnalyticsEvent,
        severity: MacAnalyticsSeverity,
        source: String,
        errorKind: String,
        properties: [String: String]
    ) async {
        guard isEnabled() else { return }

        let payload: [String: Any] = [
            "event": event.rawValue,
            "severity": severity.rawValue,
            "source": source,
            "error_kind": errorKind,
            "properties": properties,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sharedSecret {
            request.setValue(sharedSecret, forHTTPHeaderField: "X-Cmux-Bug-Alerts-Secret")
        }
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return
            }
        } catch {
            return
        }
    }

    private static func defaultEndpoint() -> URL {
        if let override = ProcessInfo.processInfo.environment["CMUX_BUG_ALERTS_API_URL"],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        return URL(string: "https://cmux.com/api/bug-alerts")!
    }

    private static func defaultSharedSecret() -> String? {
        ProcessInfo.processInfo.environment["CMUX_BUG_ALERTS_SHARED_SECRET"]
    }
}
