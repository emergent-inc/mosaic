public import Foundation

/// Builds the browser share link for a collaboration session code.
///
/// The link opens the web sharing client (sharing.mosaic.inc), where guests
/// join the session anonymously from a browser. Every surface that offers a
/// "copy link" action (session-created dialog, terminal share popover, CLI)
/// must build the URL through this helper so the link shape stays uniform.
public enum CollaborationShareLink {
    /// The production web sharing client origin.
    public static let defaultBaseURLString = "https://sharing.mosaic.inc"

    /// Environment variable that overrides the share-link origin (staging or
    /// local sharing-app development).
    public static let baseURLEnvironmentKey = "MOSAIC_SHARING_BASE_URL"

    /// The browser join URL for a session code, or `nil` when the code is
    /// empty after trimming.
    /// - Parameters:
    ///   - sessionCode: The session code shown to the host (any format the
    ///     code entry accepts; used verbatim after trimming).
    ///   - baseURLString: Origin override; defaults to the
    ///     ``baseURLEnvironmentKey`` environment value, then the production
    ///     origin.
    /// - Returns: A URL of the form `https://sharing.mosaic.inc/s/<CODE>`.
    public static func url(
        forSessionCode sessionCode: String,
        baseURLString: String? = nil
    ) -> URL? {
        let code = sessionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let base = resolvedBaseURLString(baseURLString)
        guard var components = URLComponents(string: base) else { return nil }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = "\(basePath)/s/\(code)"
        return components.url
    }

    private static func resolvedBaseURLString(_ override: String?) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        if let fromEnvironment = ProcessInfo.processInfo.environment[baseURLEnvironmentKey],
           !fromEnvironment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromEnvironment
        }
        return defaultBaseURLString
    }
}
