import CMUXAuthCore
import Foundation
import Testing
@testable import CmuxAuthRuntime

@Suite(.serialized)
struct NativeAuthClientTests {
    @Test
    func currentUserFetchesMeWithStoredAccessToken() async throws {
        let store = FlowInMemoryTokenStore()
        await store.setTokens(accessToken: "access-1", refreshToken: "refresh-1")
        let client = NativeAuthClient(
            apiBaseURL: try #require(URL(string: "https://cmux.test")),
            tokenStore: store,
            session: Self.urlSession()
        )

        NativeAuthClientURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/auth/native/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            return try Self.jsonResponse([
                "user": [
                    "id": "user_clerk",
                    "displayName": "Clerk User",
                    "primaryEmail": "clerk@example.com",
                    "imageURL": "https://img.example/clerk.png",
                ],
                "teams": [
                    ["id": "org_1", "displayName": "Team One"],
                ],
                "selectedTeamId": "org_1",
            ])
        }
        defer { NativeAuthClientURLProtocol.reset() }

        let user = try await client.currentUser(throwOnMissing: true)
        let teams = try await client.listTeams()

        #expect(user == CMUXAuthUser(
            id: "user_clerk",
            primaryEmail: "clerk@example.com",
            displayName: "Clerk User",
            imageURL: "https://img.example/clerk.png"
        ))
        #expect(teams == [CMUXAuthTeam(id: "org_1", displayName: "Team One")])
    }

    @Test
    func currentUserMapsMissingImageURLToNil() async throws {
        let store = FlowInMemoryTokenStore()
        await store.setTokens(accessToken: "access-1", refreshToken: "refresh-1")
        let client = NativeAuthClient(
            apiBaseURL: try #require(URL(string: "https://cmux.test")),
            tokenStore: store,
            session: Self.urlSession()
        )

        NativeAuthClientURLProtocol.handler = { _ in
            // A /me response from a legacy token carries no imageURL field.
            try Self.jsonResponse([
                "user": [
                    "id": "user_clerk",
                    "displayName": "Clerk User",
                    "primaryEmail": "clerk@example.com",
                ],
                "teams": [],
                "selectedTeamId": NSNull(),
            ])
        }
        defer { NativeAuthClientURLProtocol.reset() }

        let user = try await client.currentUser(throwOnMissing: true)

        #expect(user?.id == "user_clerk")
        #expect(user?.imageURL == nil)
    }

    @Test
    func currentUserRefreshesExpiredAccessTokenAndPersistsNewPair() async throws {
        let store = FlowInMemoryTokenStore()
        await store.setTokens(accessToken: "expired-access", refreshToken: "refresh-1")
        let client = NativeAuthClient(
            apiBaseURL: try #require(URL(string: "https://cmux.test")),
            tokenStore: store,
            session: Self.urlSession()
        )
        var meRequests = 0

        NativeAuthClientURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/native/me":
                meRequests += 1
                if meRequests == 1 {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access")
                    return try Self.emptyResponse(status: 401, request: request)
                }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access")
                return try Self.jsonResponse([
                    "user": [
                        "id": "user_clerk",
                        "displayName": "Clerk User",
                        "primaryEmail": "clerk@example.com",
                        "imageURL": "https://img.example/fresh-clerk.png",
                    ],
                    "teams": [],
                    "selectedTeamId": NSNull(),
                ])
            case "/api/auth/native/refresh":
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "X-Mosaic-Refresh-Token") == "refresh-1")
                return try Self.jsonResponse([
                    "accessToken": "fresh-access",
                    "refreshToken": "fresh-refresh",
                ])
            default:
                Issue.record("Unexpected native auth request: \(request.url?.absoluteString ?? "<nil>")")
                return try Self.emptyResponse(status: 404, request: request)
            }
        }
        defer { NativeAuthClientURLProtocol.reset() }

        let user = try await client.currentUser(throwOnMissing: true)

        #expect(user?.id == "user_clerk")
        #expect(user?.displayName == "Clerk User")
        #expect(user?.primaryEmail == "clerk@example.com")
        #expect(user?.imageURL == "https://img.example/fresh-clerk.png")
        #expect(meRequests == 2)
        #expect(await store.getStoredAccessToken() == "fresh-access")
        #expect(await store.getStoredRefreshToken() == "fresh-refresh")
    }

    @Test
    func currentUserReturnsNilWhenRefreshFailsAndThrowOnMissingIsFalse() async throws {
        let store = FlowInMemoryTokenStore()
        await store.setTokens(accessToken: "expired-access", refreshToken: "refresh-1")
        let client = NativeAuthClient(
            apiBaseURL: try #require(URL(string: "https://cmux.test")),
            tokenStore: store,
            session: Self.urlSession()
        )

        NativeAuthClientURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/native/me":
                return try Self.emptyResponse(status: 401, request: request)
            case "/api/auth/native/refresh":
                return try Self.emptyResponse(status: 401, request: request)
            default:
                return try Self.emptyResponse(status: 404, request: request)
            }
        }
        defer { NativeAuthClientURLProtocol.reset() }

        let user = try await client.currentUser(throwOnMissing: false)

        #expect(user == nil)
        #expect(await store.getStoredAccessToken() == "expired-access")
        #expect(await store.getStoredRefreshToken() == "refresh-1")
    }

    private static func urlSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeAuthClientURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(_ object: Any) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: try #require(URL(string: "https://cmux.test")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        return (try #require(response), data)
    }

    private static func emptyResponse(status: Int, request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )
        return (try #require(response), Data())
    }
}

private final class NativeAuthClientURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
