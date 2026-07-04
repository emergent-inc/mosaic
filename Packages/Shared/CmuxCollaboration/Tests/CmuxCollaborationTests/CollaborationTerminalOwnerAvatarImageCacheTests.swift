import Foundation
import Testing

@testable import CmuxCollaboration

private enum FakeFetchError: Error { case offline }

/// Scripts a sequence of fetch results so the cache can be driven deterministically.
private actor ScriptedAvatarFetcher {
    private var results: [Result<CollaborationTerminalOwnerAvatarFetchResponse, any Error>]
    private(set) var callCount = 0

    init(_ results: [Result<CollaborationTerminalOwnerAvatarFetchResponse, any Error>]) {
        self.results = results
    }

    func fetch(_ url: URL) async throws -> CollaborationTerminalOwnerAvatarFetchResponse {
        callCount += 1
        // Repeat the final scripted result for any extra calls.
        let index = min(callCount - 1, results.count - 1)
        switch results[index] {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

/// Thread-safe recorder for the synchronous logging callbacks.
private final class Recorder<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    var all: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func response(_ bytes: Int, status: Int? = 200) -> CollaborationTerminalOwnerAvatarFetchResponse {
    CollaborationTerminalOwnerAvatarFetchResponse(
        data: Data(repeating: 0xAB, count: bytes),
        statusCode: status
    )
}

private let avatarURL = URL(string: "https://img.clerk.com/example.png")!

struct CollaborationTerminalOwnerAvatarFetchPolicyTests {
    @Test
    func acceptsSuccessfulNonEmptyPayload() {
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 200, byteCount: 1024) == .accept)
    }

    @Test
    func acceptsResponseWithoutHTTPStatus() {
        // A non-HTTP response (statusCode nil) with a real body is still usable,
        // matching the sidebar's lenient AsyncImage.
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: nil, byteCount: 512) == .accept)
    }

    @Test
    func rejectsNonSuccessStatus() {
        #expect(
            CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 404, byteCount: 1024)
                == .rejectNonSuccessStatus(404)
        )
        #expect(
            CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 500, byteCount: 1024)
                == .rejectNonSuccessStatus(500)
        )
    }

    @Test
    func acceptsStatusBoundaries() {
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 200, byteCount: 1) == .accept)
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 299, byteCount: 1) == .accept)
        #expect(
            CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 199, byteCount: 1)
                == .rejectNonSuccessStatus(199)
        )
        #expect(
            CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 300, byteCount: 1)
                == .rejectNonSuccessStatus(300)
        )
    }

    @Test
    func rejectsEmptyPayload() {
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 200, byteCount: 0) == .rejectEmpty)
    }

    @Test
    func rejectsOversizePayload() {
        let max = CollaborationTerminalOwnerAvatarFetchPolicy.maximumImageBytes
        #expect(CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 200, byteCount: max) == .accept)
        #expect(
            CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(statusCode: 200, byteCount: max + 1)
                == .rejectTooLarge(byteCount: max + 1)
        )
    }
}

struct CollaborationTerminalOwnerAvatarImageCacheTests {
    @Test
    func returnsAndCachesSuccessfulPayload() async {
        let fetcher = ScriptedAvatarFetcher([.success(response(64))])
        let cache = CollaborationTerminalOwnerAvatarImageCache(fetcher: { try await fetcher.fetch($0) })

        let first = await cache.imageData(for: avatarURL)
        #expect(first?.count == 64)

        // A second read is served from cache without re-fetching.
        let second = await cache.imageData(for: avatarURL)
        #expect(second?.count == 64)
        #expect(await fetcher.callCount == 1)
        #expect(await cache.cachedByteCount(for: avatarURL) == 64)
    }

    @Test
    func transientFailureDoesNotPermanentlyBlockLaterSuccess() async {
        // The regression: the tab showed initials forever because a single
        // failed fetch was cached permanently. A thrown error must NOT poison
        // the URL — the next request has to retry and succeed.
        let errors = Recorder<URL>()
        let fetcher = ScriptedAvatarFetcher([
            .failure(FakeFetchError.offline),
            .success(response(128)),
        ])
        let cache = CollaborationTerminalOwnerAvatarImageCache(
            fetcher: { try await fetcher.fetch($0) },
            onError: { url, _ in errors.append(url) }
        )

        let failed = await cache.imageData(for: avatarURL)
        #expect(failed == nil)
        #expect(await cache.cachedByteCount(for: avatarURL) == nil)

        let recovered = await cache.imageData(for: avatarURL)
        #expect(recovered?.count == 128)
        #expect(await fetcher.callCount == 2)
        #expect(errors.all == [avatarURL])
    }

    @Test
    func nonSuccessStatusIsNotCachedAndRetries() async {
        let outcomes = Recorder<CollaborationTerminalOwnerAvatarFetchOutcome>()
        let fetcher = ScriptedAvatarFetcher([
            .success(response(64, status: 403)),
            .success(response(200, status: 200)),
        ])
        let cache = CollaborationTerminalOwnerAvatarImageCache(
            fetcher: { try await fetcher.fetch($0) },
            onOutcome: { _, outcome in outcomes.append(outcome) }
        )

        let rejected = await cache.imageData(for: avatarURL)
        #expect(rejected == nil)
        #expect(await cache.cachedByteCount(for: avatarURL) == nil)

        let accepted = await cache.imageData(for: avatarURL)
        #expect(accepted?.count == 200)
        #expect(outcomes.all == [.rejectNonSuccessStatus(403)])
    }

    @Test
    func emptyPayloadIsRejected() async {
        let outcomes = Recorder<CollaborationTerminalOwnerAvatarFetchOutcome>()
        let fetcher = ScriptedAvatarFetcher([.success(response(0))])
        let cache = CollaborationTerminalOwnerAvatarImageCache(
            fetcher: { try await fetcher.fetch($0) },
            onOutcome: { _, outcome in outcomes.append(outcome) }
        )

        let result = await cache.imageData(for: avatarURL)
        #expect(result == nil)
        #expect(outcomes.all == [.rejectEmpty])
    }

    @Test
    func oversizePayloadIsRejected() async {
        let outcomes = Recorder<CollaborationTerminalOwnerAvatarFetchOutcome>()
        let tooBig = CollaborationTerminalOwnerAvatarFetchPolicy.maximumImageBytes + 1
        let fetcher = ScriptedAvatarFetcher([.success(response(tooBig))])
        let cache = CollaborationTerminalOwnerAvatarImageCache(
            fetcher: { try await fetcher.fetch($0) },
            onOutcome: { _, outcome in outcomes.append(outcome) }
        )

        let result = await cache.imageData(for: avatarURL)
        #expect(result == nil)
        #expect(outcomes.all == [.rejectTooLarge(byteCount: tooBig)])
    }
}
