import AppKit
import MosaicAuthCore
import MosaicAuthRuntime
import MosaicSettingsUI
import Foundation

/// Adapts the shared ``MosaicAuthRuntime/AuthCoordinator`` and the macOS
/// ``HostBrowserSignInFlow`` to the `MosaicSettingsUI` `AccountFlow` protocol so
/// the `AccountSection` can drive sign-in / sign-out / team selection without
/// depending on the auth packages.
///
/// A pure projection: every property reads through the coordinator's (or the
/// browser flow's) `@Observable` storage, so SwiftUI views that read this
/// adapter in `body` re-render when the underlying auth state changes.
@MainActor
final class HostAccountFlow: AccountFlow {
    private let coordinator: AuthCoordinator
    private let browserSignIn: HostBrowserSignInFlow

    init(coordinator: AuthCoordinator, browserSignIn: HostBrowserSignInFlow) {
        self.coordinator = coordinator
        self.browserSignIn = browserSignIn
    }

    var currentIdentity: AccountIdentity? {
        Self.identity(from: coordinator.currentUser)
    }

    var availableTeams: [AccountTeamSummary] {
        coordinator.availableTeams.map { team in
            AccountTeamSummary(
                id: team.id,
                displayName: team.displayName,
                slug: team.slug,
                workspaceType: team.workspaceType,
                planTier: team.planTier
            )
        }
    }

    var selectedTeamID: String? {
        get { coordinator.selectedTeamID }
        set { coordinator.selectedTeamID = newValue }
    }

    var isWorkingOnAuth: Bool {
        coordinator.isLoading || coordinator.isRestoringSession || browserSignIn.isSigningIn
    }

    var signInIsSlow: Bool {
        browserSignIn.signInIsSlow
    }

    func startSignIn() {
        browserSignIn.beginSignIn()
    }

    func openSignInInDefaultBrowser() {
        guard let url = browserSignIn.activeAttemptSignInURL else { return }
        NSWorkspace.shared.open(url)
    }

    func signOut() async {
        await browserSignIn.signOut()
    }

    func refreshCurrentUser() async {
        // The coordinator refreshes the user on sign-in and session restore;
        // there is no cheaper public refresh path. If the cached identity is
        // stale the user signs in again (full browser round trip).
    }

    private static func identity(from user: MosaicAuthUser?) -> AccountIdentity? {
        guard let user else { return nil }
        let trimmedImageURL = user.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let avatarURL = trimmedImageURL.isEmpty ? nil : URL(string: trimmedImageURL)
        return AccountIdentity(
            id: user.id,
            displayName: user.displayName ?? "",
            email: user.primaryEmail ?? "",
            avatarURL: avatarURL
        )
    }
}
