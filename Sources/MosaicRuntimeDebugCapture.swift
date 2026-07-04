import Foundation

enum MosaicRuntimeDebugCapture {
    private static let configuration: MosaicRuntimeDebugCaptureConfiguration? = {
        let env = ProcessInfo.processInfo.environment
        guard let baseURLString = env["MOSAIC_RUNTIME_DEBUG_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let baseURL = URL(string: baseURLString),
              let token = env["MOSAIC_RUNTIME_DEBUG_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              let sessionID = env["MOSAIC_RUNTIME_DEBUG_SESSION_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty else {
            return nil
        }
        return MosaicRuntimeDebugCaptureConfiguration(baseURL: baseURL, token: token, sessionID: sessionID)
    }()

    private static let sender = MosaicRuntimeDebugCaptureSender(maxInFlightRequests: 16)

    static func logIfConfigured(
        hypothesisID: String,
        source: String,
        name: String,
        expected: String? = nil,
        actual: String? = nil,
        data: [String: Any] = [:]
    ) {
        guard let configuration else { return }

        Task(priority: .utility) {
            await sender.sendIfCapacityAvailable(
                configuration: configuration,
                hypothesisID: hypothesisID,
                source: source,
                name: name,
                expected: expected,
                actual: actual,
                data: data
            )
        }
    }
}
