import CMUXAuthCore
import CmuxAuthRuntime
import Foundation
import Observation

@MainActor
final class MacAuthAnalyticsIdentityObserver {
    private weak var coordinator: AuthCoordinator?
    private var lastState: AuthAnalyticsIdentityState?

    func start(coordinator: AuthCoordinator) {
        self.coordinator = coordinator
        publishIfNeeded()
        observe()
    }

    private func observe() {
        guard let coordinator else { return }
        withObservationTracking {
            _ = coordinator.isAuthenticated
            _ = coordinator.currentUser?.id
            _ = coordinator.resolvedTeamID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publishIfNeeded()
                self?.observe()
            }
        }
    }

    private func publishIfNeeded() {
        guard let coordinator else { return }
        let state = AuthAnalyticsIdentityState(
            isAuthenticated: coordinator.isAuthenticated,
            userID: coordinator.currentUser?.id,
            teamID: coordinator.resolvedTeamID
        )
        guard state != lastState else { return }

        let previous = lastState
        lastState = state

        if state.isAuthenticated, let userID = state.userID, !userID.isEmpty {
            var properties: [String: Any] = [
                "auth_state": "authenticated",
            ]
            if let teamID = state.teamID, !teamID.isEmpty {
                properties["team_id"] = teamID
            }
            PostHogAnalytics.shared.identifyAuthenticatedUser(userID: userID, properties: properties)
        } else if previous?.isAuthenticated == true {
            PostHogAnalytics.shared.resetIdentity()
        }
    }
}

private struct AuthAnalyticsIdentityState: Equatable {
    let isAuthenticated: Bool
    let userID: String?
    let teamID: String?
}
