import Foundation

/// The token pair carried by a Mosaic auth callback URL
/// (`mosaic://auth-callback?mosaic_refresh=…&mosaic_access=…`).
public struct AuthCallbackPayload: Equatable, Sendable {
    /// The Mosaic-native refresh token from the callback.
    public let refreshToken: String
    /// The Mosaic-native access token from the callback.
    public let accessToken: String

    /// Creates a payload from its parts.
    public init(refreshToken: String, accessToken: String) {
        self.refreshToken = refreshToken
        self.accessToken = accessToken
    }
}
