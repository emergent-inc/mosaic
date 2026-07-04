/// The current collaboration role of a shareable surface.
public enum CollaborationSurfaceSharingRole: Equatable, Sendable {
    /// The local surface is not shared or mirrored.
    case notShared
    /// The local user is hosting this surface for collaborators.
    case hosted
    /// The local surface is a mirror of another collaborator's shared surface.
    case mirrored
}
