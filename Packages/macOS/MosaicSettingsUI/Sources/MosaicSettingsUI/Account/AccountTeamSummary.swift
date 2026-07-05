import Foundation

/// Display-only view of a mosaic team the current user belongs to.
///
/// Surface for the package's ``AccountSection`` to render the team
/// picker. The host derives this from its own team type.
public struct AccountTeamSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let slug: String?
    /// The org's workspace identity (`"personal"` / `"team"`), when known.
    public let workspaceType: String?
    /// The org's resolved plan tier (`"hobby"` / `"team"` / `"enterprise"`),
    /// when known. Used to render a plan badge next to the team name.
    public let planTier: String?

    public init(
        id: String,
        displayName: String,
        slug: String? = nil,
        workspaceType: String? = nil,
        planTier: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.slug = slug
        self.workspaceType = workspaceType
        self.planTier = planTier
    }

    /// A short, user-facing account-kind label derived from the workspace type
    /// and plan tier: `Enterprise` for enterprise plans, else `Team` for team
    /// workspaces/plans, else `Personal`. Returns `nil` when the backend
    /// exposed neither field (e.g. the legacy Stack Auth path) so the UI can
    /// fall back to showing just the name.
    public var accountKindLabel: String? {
        let tier = planTier?.lowercased()
        let type = workspaceType?.lowercased()
        if tier == "enterprise" { return "Enterprise" }
        if tier == "team" || type == "team" { return "Team" }
        if type == "personal" || tier == "hobby" { return "Personal" }
        return nil
    }
}
