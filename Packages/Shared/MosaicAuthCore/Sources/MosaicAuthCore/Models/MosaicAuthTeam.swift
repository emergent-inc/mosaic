import Foundation

/// A team the signed-in user belongs to.
///
/// Mirrors the Stack Auth team summary the apps surface in account UI and
/// expose over the mosaic socket (`auth.status`). Codable so consumers can cache
/// the team list alongside the cached user.
public struct MosaicAuthTeam: Codable, Equatable, Identifiable, Sendable {
    /// The Stack Auth team id.
    public let id: String
    /// The team's human-readable display name.
    public let displayName: String
    /// The team's URL slug, when the backend exposes one.
    public let slug: String?
    /// The org's workspace identity (`"personal"` / `"team"`), when the backend
    /// exposes it. Optional/additive so cached teams from older builds (and the
    /// legacy Stack Auth path, which never sets it) decode as `nil`.
    public let workspaceType: String?
    /// The org's resolved plan tier (`"hobby"` / `"team"` / `"enterprise"`),
    /// when the backend exposes it. Optional/additive for the same reason.
    public let planTier: String?

    /// Creates a team summary.
    /// - Parameters:
    ///   - id: The Stack Auth team id.
    ///   - displayName: The team's human-readable display name.
    ///   - slug: The team's URL slug, when known.
    ///   - workspaceType: The org's workspace identity, when known.
    ///   - planTier: The org's resolved plan tier, when known.
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
}
