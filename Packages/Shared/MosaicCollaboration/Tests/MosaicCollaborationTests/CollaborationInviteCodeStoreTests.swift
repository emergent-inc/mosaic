import MosaicCollaboration
import Foundation
import Testing

@Suite(.serialized)
struct CollaborationInviteCodeStoreTests {
    @Test
    func normalizedSessionCodeAcceptsFourCharacterInvitesAndLegacyCodes() throws {
        let store = try makeStore()

        #expect(store.normalizedSessionCode(from: "5znh") == "5ZNH")
        #expect(store.normalizedSessionCode(from: "5z-nh") == "5ZNH")
        #expect(store.normalizedSessionCode(from: "5ZNH GF9P") == "5ZNHGF9P")
        #expect(store.normalizedSessionCode(from: "abcde") == "ABCDE")
        #expect(store.normalizedSessionCode(from: " abc ") == "ABC")
    }

    @Test
    func rememberedSessionCodesAreMostRecentFirstDedupedAndBounded() throws {
        let store = try makeStore(maxRecentSessionCodes: 3)

        store.rememberSessionCode("5z-nh")
        store.rememberSessionCode("8abc")
        store.rememberSessionCode("5ZNH")
        store.rememberSessionCode("9def")
        store.rememberSessionCode("7ghi")

        #expect(store.recentSessionCodes() == ["7GHI", "9DEF", "5ZNH"])
    }

    @Test
    func recentSessionCodesNormalizePersistedLegacyValuesAndSkipBlanks() throws {
        let suite = "mosaic-collaboration-invite-code-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["5z-nh", " ", "5ZNH", "5znh gf9p"], forKey: "recent")
        let store = CollaborationInviteCodeStore(
            defaults: defaults,
            recentSessionCodesKey: "recent",
            maxRecentSessionCodes: 8
        )

        #expect(store.recentSessionCodes() == ["5ZNH", "5ZNHGF9P"])
    }

    private func makeStore(maxRecentSessionCodes: Int = 8) throws -> CollaborationInviteCodeStore {
        let suite = "mosaic-collaboration-invite-code-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CollaborationInviteCodeStore(
            defaults: defaults,
            recentSessionCodesKey: "recent",
            maxRecentSessionCodes: maxRecentSessionCodes
        )
    }
}
