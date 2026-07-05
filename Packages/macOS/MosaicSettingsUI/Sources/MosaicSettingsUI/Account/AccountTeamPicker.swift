import SwiftUI

/// Picker bound to the host's ``AccountFlow/selectedTeamID`` so the
/// user can switch between teams without leaving Settings.
///
/// Each row is labeled `Name — Personal / Team / Enterprise` when the backend
/// exposes the org's account kind, so a user who holds both a personal
/// workspace and one or more team/enterprise orgs can tell them apart.
@MainActor
struct AccountTeamPicker: View {
    let flow: AccountFlow

    var body: some View {
        Picker(
            String(localized: "settings.account.activeTeam", defaultValue: "Active Team"),
            selection: Binding(
                get: { flow.selectedTeamID ?? "" },
                set: { newValue in
                    flow.selectedTeamID = newValue.isEmpty ? nil : newValue
                }
            )
        ) {
            Text(String(localized: "settings.account.activeTeam.none", defaultValue: "None")).tag("")
            ForEach(flow.availableTeams) { team in
                Text(Self.rowLabel(for: team)).tag(team.id)
            }
        }
    }

    private static func rowLabel(for team: AccountTeamSummary) -> String {
        guard let kind = team.accountKindLabel else { return team.displayName }
        return "\(team.displayName) — \(kind)"
    }
}
