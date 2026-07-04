import Observation
import Testing
@testable import CmuxCollaboration

/// Stand-in for the auth coordinator: an observable user record whose fields
/// hydrate over time (launch restore, token refresh).
@MainActor
@Observable
private final class ObservableUserStore {
    var displayName: String?
    var imageURL: String?
}

@MainActor
private final class RefreshCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Waits for the refresher's main-actor change hop to land.
@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool
) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
}

@MainActor
@Suite struct CollaborationIdentityAutoRefresherTests {
    @Test func refreshesOnceImmediatelyAtStart() {
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: { _ = store.imageURL })

        #expect(counter.count == 1)
    }

    @Test func refreshesWhenProfileImageHydratesAfterStart() async {
        // The bug this type exists for: the user record gains its profile
        // image URL only after launch-restore validation completes, and the
        // collaboration identity must pick that up without user interaction.
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: {
            _ = store.displayName
            _ = store.imageURL
        })
        #expect(counter.count == 1)

        store.imageURL = "https://example.com/avatar.png"

        await waitUntil { counter.count >= 2 }
        #expect(counter.count == 2)
    }

    @Test func reArmsAfterEachChange() async {
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: { _ = store.imageURL })

        store.imageURL = "https://example.com/a.png"
        await waitUntil { counter.count >= 2 }

        store.imageURL = "https://example.com/b.png"
        await waitUntil { counter.count >= 3 }

        #expect(counter.count == 3)
    }

    @Test func tracksEveryReadPropertyNotJustOne() async {
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: {
            _ = store.displayName
            _ = store.imageURL
        })

        store.displayName = "Alice"
        await waitUntil { counter.count >= 2 }
        #expect(counter.count == 2)
    }

    @Test func stopDropsPendingAndFutureChanges() async {
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: { _ = store.imageURL })
        refresher.stop()

        store.imageURL = "https://example.com/a.png"
        // Give a pending (now-cancelled-by-stop) hop every chance to run.
        for _ in 0..<50 { await Task.yield() }

        #expect(counter.count == 1)
    }

    @Test func untrackedPropertyDoesNotTriggerRefresh() async {
        let counter = RefreshCounter()
        let refresher = CollaborationIdentityAutoRefresher(refresh: { counter.increment() })
        let store = ObservableUserStore()

        refresher.start(trackUser: { _ = store.imageURL })

        store.displayName = "Alice"
        for _ in 0..<50 { await Task.yield() }

        #expect(counter.count == 1)
    }
}
