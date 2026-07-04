import Foundation

/// Persists the signed-in ``MosaicAuthUser`` across launches.
///
/// The cached identity lets the apps render the account card immediately at
/// launch while the network session validates. Backed by an injected
/// ``MosaicAuthKeyValueStore`` under a caller-chosen key (JSON-encoded), so each
/// app keeps its historical defaults key and tests use an in-memory store.
///
/// `@unchecked Sendable`: the injected key-value store (production:
/// `UserDefaults`) is Apple-documented thread-safe, and the JSON coders are
/// stateless between calls.
public final class MosaicAuthIdentityStore: @unchecked Sendable {
    private let keyValueStore: MosaicAuthKeyValueStore
    private let key: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Creates an identity store.
    /// - Parameters:
    ///   - keyValueStore: The injected key-value backing store.
    ///   - key: The key the encoded user persists under.
    public init(keyValueStore: MosaicAuthKeyValueStore, key: String) {
        self.keyValueStore = keyValueStore
        self.key = key
    }

    /// Persist `user` as the cached identity.
    /// - Throws: An encoding error if the user could not be serialized.
    public func save(_ user: MosaicAuthUser) throws {
        let data = try encoder.encode(user)
        keyValueStore.set(data, forKey: key)
    }

    /// Load the cached identity, or `nil` when none is stored.
    /// - Throws: A decoding error if the stored blob is corrupt.
    public func load() throws -> MosaicAuthUser? {
        guard let data = keyValueStore.data(forKey: key) else {
            return nil
        }
        return try decoder.decode(MosaicAuthUser.self, from: data)
    }

    /// Remove the cached identity.
    public func clear() {
        keyValueStore.removeObject(forKey: key)
    }
}
