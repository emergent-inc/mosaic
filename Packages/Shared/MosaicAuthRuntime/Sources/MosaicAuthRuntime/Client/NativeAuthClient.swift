public import MosaicAuthCore
public import Foundation

/// Auth client backed by Mosaic-native tokens minted from a Clerk website session.
public actor NativeAuthClient: AuthClient {
    private struct TokenPair: Decodable {
        let accessToken: String
        let refreshToken: String
    }

    private struct MeResponse: Decodable {
        struct User: Decodable {
            let id: String
            let displayName: String?
            let primaryEmail: String?
            let imageURL: String?
        }

        struct Team: Decodable {
            let id: String
            let displayName: String?
            let workspaceType: String?
            let planTier: String?
        }

        let user: User
        let teams: [Team]
        let selectedTeamId: String?
    }

    private let apiBaseURL: URL
    private let tokenStore: any StackAuthTokenStoreProtocol
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// Creates a native auth client.
    /// - Parameters:
    ///   - apiBaseURL: The Mosaic web/API origin.
    ///   - tokenStore: The local token persistence seam.
    ///   - session: URL session used for API calls.
    public init(
        apiBaseURL: URL,
        tokenStore: any StackAuthTokenStoreProtocol,
        session: URLSession? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.tokenStore = tokenStore
        self.session = session ?? URLSession.shared
    }

    public func accessToken() async -> String? {
        await tokenStore.currentAccessToken()
    }

    public func refreshToken() async -> String? {
        await tokenStore.currentRefreshToken()
    }

    public func forceRefreshAccessToken() async -> String? {
        guard let refreshToken = await tokenStore.currentRefreshToken(),
              let tokens = try? await refreshTokens(refreshToken: refreshToken) else {
            return nil
        }
        await tokenStore.seed(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
        return tokens.accessToken
    }

    public func currentUser(throwOnMissing: Bool) async throws -> MosaicAuthUser? {
        guard let response = try await me(allowRefresh: true) else {
            if throwOnMissing {
                throw AuthError.unauthorized
            }
            return nil
        }
        return MosaicAuthUser(
            id: response.user.id,
            primaryEmail: response.user.primaryEmail,
            displayName: response.user.displayName,
            imageURL: response.user.imageURL
        )
    }

    public func listTeams() async throws -> [MosaicAuthTeam] {
        guard let response = try await me(allowRefresh: true) else { return [] }
        return response.teams.map {
            MosaicAuthTeam(
                id: $0.id,
                displayName: $0.displayName ?? $0.id,
                workspaceType: $0.workspaceType,
                planTier: $0.planTier
            )
        }
    }

    public func serverSelectedTeamID() async throws -> String? {
        guard let response = try await me(allowRefresh: true) else { return nil }
        return response.selectedTeamId
    }

    public func sendMagicLinkEmail(email: String, callbackURL: String) async throws -> String {
        throw AuthError.serverError(400, "browser_sign_in_required")
    }

    public func signInWithMagicLink(code: String) async throws {
        throw AuthError.serverError(400, "browser_sign_in_required")
    }

    public func signInWithCredential(email: String, password: String) async throws {
        throw AuthError.serverError(400, "browser_sign_in_required")
    }

    public func signInWithOAuth(provider: String, anchor: any AuthPresentationAnchoring) async throws {
        throw AuthError.serverError(400, "browser_sign_in_required")
    }

    public func storedAccessToken() async -> String? {
        await tokenStore.currentAccessToken()
    }

    public func clearLocalSession() async {
        await tokenStore.clear()
    }

    public func clearLocalSession(ifRefreshTokenMatches refreshToken: String) async {
        await tokenStore.clearTokensIfCurrent(accessToken: nil, refreshToken: refreshToken)
    }

    public func revokeSession(accessToken: String?, refreshToken: String?) async throws {
        guard let refreshToken, !refreshToken.isEmpty else { return }
        var request = URLRequest(url: endpoint("api/auth/native/revoke"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(refreshToken, forHTTPHeaderField: "X-Mosaic-Refresh-Token")
        _ = try? await session.data(for: request)
    }

    public func freshAccessToken(accessToken: String?, refreshToken: String) async -> String? {
        if let tokens = try? await refreshTokens(refreshToken: refreshToken) {
            return tokens.accessToken
        }
        return accessToken
    }

    private func me(allowRefresh: Bool) async throws -> MeResponse? {
        guard let accessToken = await tokenStore.currentAccessToken() else {
            return nil
        }
        let result = try await me(accessToken: accessToken)
        switch result {
        case .success(let response):
            return response
        case .unauthorized where allowRefresh:
            guard let refreshed = await forceRefreshAccessToken() else { return nil }
            if case .success(let response) = try await me(accessToken: refreshed) {
                return response
            }
            return nil
        case .unauthorized:
            return nil
        }
    }

    private enum MeResult {
        case success(MeResponse)
        case unauthorized
    }

    private func me(accessToken: String) async throws -> MeResult {
        var request = URLRequest(url: endpoint("api/auth/native/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        if http.statusCode == 401 {
            return .unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.serverError(http.statusCode, "native_auth_me_failed")
        }
        return .success(try decoder.decode(MeResponse.self, from: data))
    }

    private func refreshTokens(refreshToken: String) async throws -> TokenPair {
        var request = URLRequest(url: endpoint("api/auth/native/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(refreshToken, forHTTPHeaderField: "X-Mosaic-Refresh-Token")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.unauthorized
        }
        return try decoder.decode(TokenPair.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        apiBaseURL.appending(path: path)
    }
}
