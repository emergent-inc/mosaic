public import Foundation

/// Stores and normalizes collaboration invite codes.
public struct CollaborationInviteCodeStore {
    /// The default key used for recently joined collaboration sessions.
    public static let defaultRecentSessionCodesKey = "collaboration.recentSessionCodes"

    private let defaults: UserDefaults
    private let recentSessionCodesKey: String
    private let maxRecentSessionCodes: Int

    /// Creates an invite-code store.
    /// - Parameters:
    ///   - defaults: The defaults domain that persists recent invite codes.
    ///   - recentSessionCodesKey: The key used for recent invite codes.
    ///   - maxRecentSessionCodes: The maximum number of recent codes to keep.
    public init(
        defaults: UserDefaults = .standard,
        recentSessionCodesKey: String = Self.defaultRecentSessionCodesKey,
        maxRecentSessionCodes: Int = 8
    ) {
        self.defaults = defaults
        self.recentSessionCodesKey = recentSessionCodesKey
        self.maxRecentSessionCodes = maxRecentSessionCodes
    }

    /// Returns a compact uppercase invite code while preserving supported code lengths.
    /// - Parameter value: The raw invite code as typed or pasted by a user.
    /// - Returns: A normalized invite code suitable for relay URLs and recent-code storage.
    public func normalizedSessionCode(from value: String) -> String {
        let compact = value
            .uppercased()
            .unicodeScalars
            .filter { scalar in
                (65...90).contains(scalar.value) || (48...57).contains(scalar.value)
            }
            .map(String.init)
            .joined()
        if compact.count == 4 {
            return compact
        }
        if compact.count == 8 {
            return compact
        }
        if compact.count == 5 {
            return compact
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Returns recent invite codes in most-recent-first order.
    public func recentSessionCodes() -> [String] {
        let rawCodes = defaults.stringArray(forKey: recentSessionCodesKey) ?? []
        var seen = Set<String>()
        return rawCodes.compactMap { code in
            let normalized = normalizedSessionCode(from: code)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    /// Records a successfully joined or created invite code for later rejoin.
    /// - Parameter code: The invite code to persist.
    public func rememberSessionCode(_ code: String) {
        let normalized = normalizedSessionCode(from: code)
        guard !normalized.isEmpty else { return }
        let remaining = recentSessionCodes().filter { $0 != normalized }
        let nextCodes = Array(([normalized] + remaining).prefix(maxRecentSessionCodes))
        defaults.set(nextCodes, forKey: recentSessionCodesKey)
    }
}
