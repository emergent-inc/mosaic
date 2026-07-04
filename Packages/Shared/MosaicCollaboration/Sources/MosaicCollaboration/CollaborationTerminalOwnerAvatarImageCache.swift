public import Foundation

/// The reason a fetched terminal-owner avatar payload was accepted or rejected.
///
/// Keeping the decision in one pure value lets the app log exactly which gate
/// dropped a profile image and lets tests pin the acceptance rules without a
/// live network.
public enum CollaborationTerminalOwnerAvatarFetchOutcome: Equatable, Sendable {
    /// The payload is a usable image body and should be cached and rendered.
    case accept
    /// The HTTP response reported a non-2xx status.
    case rejectNonSuccessStatus(Int)
    /// The payload exceeded the maximum allowed image size.
    case rejectTooLarge(byteCount: Int)
    /// The payload was empty.
    case rejectEmpty
}

/// Pure acceptance policy for a fetched terminal-owner avatar payload.
public enum CollaborationTerminalOwnerAvatarFetchPolicy {
    /// The largest avatar payload accepted, in bytes.
    public static let maximumImageBytes = 4 * 1024 * 1024

    /// Decides whether a fetched payload is a usable avatar image.
    ///
    /// The rules mirror what the sidebar's `AsyncImage` tolerates: any body that
    /// arrives on a successful (or status-less) response and is a non-empty,
    /// reasonably-sized blob is accepted for decoding.
    /// - Parameters:
    ///   - statusCode: The HTTP status code, or `nil` for a non-HTTP response.
    ///   - byteCount: The number of bytes in the response body.
    /// - Returns: The acceptance decision.
    public static func evaluate(statusCode: Int?, byteCount: Int) -> CollaborationTerminalOwnerAvatarFetchOutcome {
        if let statusCode, !(200..<300).contains(statusCode) {
            return .rejectNonSuccessStatus(statusCode)
        }
        if byteCount > maximumImageBytes {
            return .rejectTooLarge(byteCount: byteCount)
        }
        if byteCount == 0 {
            return .rejectEmpty
        }
        return .accept
    }
}

/// A single avatar fetch result, decoupled from `URLSession` so the cache is testable.
public struct CollaborationTerminalOwnerAvatarFetchResponse: Sendable {
    /// The response body.
    public let data: Data
    /// The HTTP status code, or `nil` when the response was not an HTTP response.
    public let statusCode: Int?

    /// Creates a fetch response.
    /// - Parameters:
    ///   - data: The response body.
    ///   - statusCode: The HTTP status code, or `nil`.
    public init(data: Data, statusCode: Int?) {
        self.data = data
        self.statusCode = statusCode
    }
}

/// Caches terminal-owner avatar image payloads keyed by URL.
///
/// Successful payloads are cached for the process lifetime so repeated tab
/// syncs render instantly. Crucially, failures are **never** cached: a
/// transient hiccup (offline at fetch time, a cold CDN edge, a momentary
/// 5xx/TLS blip) must retry on the next request, matching the self-retrying
/// sidebar `AsyncImage`. A permanent negative cache here was the reason a
/// terminal tab stuck on initials while the sidebar rendered the real photo.
public actor CollaborationTerminalOwnerAvatarImageCache {
    /// Fetches the raw payload for a URL. Injected so tests avoid the network.
    public typealias Fetcher = @Sendable (URL) async throws -> CollaborationTerminalOwnerAvatarFetchResponse

    private let fetcher: Fetcher
    private let onOutcome: (@Sendable (URL, CollaborationTerminalOwnerAvatarFetchOutcome) -> Void)?
    private let onError: (@Sendable (URL, any Error) -> Void)?
    private var cachedDataByURL: [String: Data] = [:]

    /// Creates an avatar image cache.
    /// - Parameters:
    ///   - fetcher: Performs the network fetch for a URL.
    ///   - onOutcome: Invoked when a payload is rejected (never for `.accept`).
    ///   - onError: Invoked when the fetcher throws.
    public init(
        fetcher: @escaping Fetcher,
        onOutcome: (@Sendable (URL, CollaborationTerminalOwnerAvatarFetchOutcome) -> Void)? = nil,
        onError: (@Sendable (URL, any Error) -> Void)? = nil
    ) {
        self.fetcher = fetcher
        self.onOutcome = onOutcome
        self.onError = onError
    }

    /// Returns usable image bytes for the URL, or `nil` if the fetch failed or
    /// the payload was rejected. Failures are not remembered and will retry.
    /// - Parameter url: The avatar image URL.
    /// - Returns: The image bytes, or `nil`.
    public func imageData(for url: URL) async -> Data? {
        let key = url.absoluteString
        if let cached = cachedDataByURL[key] {
            return cached
        }
        do {
            let response = try await fetcher(url)
            let outcome = CollaborationTerminalOwnerAvatarFetchPolicy.evaluate(
                statusCode: response.statusCode,
                byteCount: response.data.count
            )
            guard outcome == .accept else {
                onOutcome?(url, outcome)
                return nil
            }
            cachedDataByURL[key] = response.data
            return response.data
        } catch {
            onError?(url, error)
            return nil
        }
    }

    /// The number of cached bytes for a URL, or `nil` when not cached. Test seam.
    /// - Parameter url: The avatar image URL.
    /// - Returns: The cached byte count, or `nil`.
    public func cachedByteCount(for url: URL) -> Int? {
        cachedDataByURL[url.absoluteString]?.count
    }
}
