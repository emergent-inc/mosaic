internal import Observation

/// Re-derives the local collaboration peer identity whenever the observed
/// auth user changes.
///
/// The collaboration runtime snapshots the signed-in user (display name,
/// profile image URL) into its peer identity only when an explicit
/// collaboration action runs. That leaves a hole: when the auth session
/// hydrates *after* a terminal was shared (launch restore validating over the
/// network, a cached pre-`imageURL` user record being replaced, a token
/// refresh minting richer claims), the shared terminal keeps the stale
/// initials avatar until the next collaboration button press. This observer
/// closes the hole by re-running the identity refresh every time the tracked
/// auth user value changes, so owner avatars and participant snapshots
/// self-correct without user interaction.
///
/// The tracked read and the refresh action are injected closures so the type
/// stays free of auth/runtime dependencies and unit-testable: `start` arms
/// `withObservationTracking` over `trackUser`, and each change re-arms after
/// invoking `refresh` on the main actor.
@MainActor
public final class CollaborationIdentityAutoRefresher {
    private let refresh: @MainActor () -> Void
    private var trackUser: (@MainActor () -> Void)?

    /// Creates an auto-refresher.
    /// - Parameter refresh: Invoked on the main actor after the tracked user
    ///   changes (and once at `start`). Must be idempotent.
    public init(refresh: @escaping @MainActor () -> Void) {
        self.refresh = refresh
    }

    /// Begin observing.
    /// - Parameter trackUser: Reads the observable auth-user state to track
    ///   (e.g. `_ = coordinator.currentUser`). Runs inside
    ///   `withObservationTracking`, so every `@Observable` property it touches
    ///   becomes a change trigger.
    ///
    /// Calls `refresh` once immediately so a user that hydrated before
    /// observation began is still picked up.
    public func start(trackUser: @escaping @MainActor () -> Void) {
        self.trackUser = trackUser
        refresh()
        observe()
    }

    /// Stop observing. A pending change notification that fires after `stop`
    /// is dropped.
    public func stop() {
        trackUser = nil
    }

    private func observe() {
        guard let trackUser else { return }
        withObservationTracking {
            trackUser()
        } onChange: { [weak self] in
            // Observation delivers onChange at willSet; hop to the main actor
            // so the refresh reads the post-change value, then re-arm.
            Task { @MainActor in
                guard let self, self.trackUser != nil else { return }
                self.refresh()
                self.observe()
            }
        }
    }
}
