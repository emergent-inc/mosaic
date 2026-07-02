import Foundation

/// The token-store seam for hosts that seed tokens out-of-band.
///
/// The browser callback delivers cmux-native tokens after the website verifies
/// a Clerk session, so the flow seeds them directly into the store used by the
/// native API client and clears them with a compare-style guard so a racing
/// sign-in's fresh tokens are never wiped by a stale sign-out.
public protocol StackAuthTokenStoreProtocol: Sendable {
    /// The currently stored access token, without refreshing it.
    func getStoredAccessToken() async -> String?
    /// The currently stored refresh token, if any.
    func getStoredRefreshToken() async -> String?
    /// Replace both stored tokens.
    func setTokens(accessToken: String?, refreshToken: String?) async
    /// Clear both stored tokens.
    func clearTokens() async
    /// Store a freshly delivered token pair.
    func seed(accessToken: String, refreshToken: String) async
    /// Clear both tokens unconditionally.
    func clear() async
    /// The currently stored access token, if any.
    func currentAccessToken() async -> String?
    /// The currently stored refresh token, if any.
    func currentRefreshToken() async -> String?
    /// Clear the stored tokens only when they still match the expected pair.
    /// - Returns: Whether the tokens were cleared.
    @discardableResult
    func clearTokensIfCurrent(accessToken: String?, refreshToken: String?) async -> Bool
}

extension StackAuthTokenStoreProtocol {
    public func seed(accessToken: String, refreshToken: String) async {
        await setTokens(accessToken: accessToken, refreshToken: refreshToken)
    }

    public func clear() async {
        await clearTokens()
    }

    public func currentAccessToken() async -> String? {
        await getStoredAccessToken()
    }

    public func currentRefreshToken() async -> String? {
        await getStoredRefreshToken()
    }

    @discardableResult
    public func clearTokensIfCurrent(accessToken: String?, refreshToken: String?) async -> Bool {
        let snapshot = AuthTokenSnapshot(
            accessToken: await currentAccessToken(),
            refreshToken: await currentRefreshToken()
        )
        guard snapshot.matches(expectedAccessToken: accessToken, expectedRefreshToken: refreshToken) else {
            return false
        }
        await clear()
        return true
    }
}
