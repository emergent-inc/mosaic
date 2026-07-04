public import Foundation

/// Persisted association between one workspace and one collaboration session.
public struct CollaborationWorkspaceSessionBinding: Codable, Equatable, Sendable {
    /// The workspace that owns this collaboration session.
    public let workspaceID: UUID
    /// The normalized invite code for the workspace's collaboration session.
    public let sessionCode: String

    /// Creates a workspace-to-session binding.
    /// - Parameters:
    ///   - workspaceID: The workspace that owns this collaboration session.
    ///   - sessionCode: The normalized invite code for the session.
    public init(workspaceID: UUID, sessionCode: String) {
        self.workspaceID = workspaceID
        self.sessionCode = sessionCode
    }
}
