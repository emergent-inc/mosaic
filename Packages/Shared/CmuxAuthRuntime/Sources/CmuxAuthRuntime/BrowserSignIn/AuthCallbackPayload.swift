import Foundation

/// The token pair carried by a cmux auth callback URL
/// (`cmux://auth-callback?cmux_refresh=…&cmux_access=…`).
public struct AuthCallbackPayload: Equatable, Sendable {
    /// The cmux-native refresh token from the callback.
    public let refreshToken: String
    /// The cmux-native access token from the callback.
    public let accessToken: String

    /// Creates a payload from its parts.
    public init(refreshToken: String, accessToken: String) {
        self.refreshToken = refreshToken
        self.accessToken = accessToken
    }
}
