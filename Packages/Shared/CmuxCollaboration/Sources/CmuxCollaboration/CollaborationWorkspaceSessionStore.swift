public import Foundation

/// Stores the collaboration session assigned to each workspace.
public struct CollaborationWorkspaceSessionStore {
    /// The default key used for workspace-scoped collaboration sessions.
    public static let defaultWorkspaceSessionBindingsKey = "collaboration.workspaceSessionBindings"

    private let defaults: UserDefaults
    private let workspaceSessionBindingsKey: String
    private let inviteCodeStore: CollaborationInviteCodeStore

    /// Creates a workspace session store.
    /// - Parameters:
    ///   - defaults: The defaults domain that persists workspace session bindings.
    ///   - workspaceSessionBindingsKey: The key used for workspace session bindings.
    ///   - inviteCodeStore: The invite-code normalizer used before persisting session codes.
    public init(
        defaults: UserDefaults = .standard,
        workspaceSessionBindingsKey: String = Self.defaultWorkspaceSessionBindingsKey,
        inviteCodeStore: CollaborationInviteCodeStore = CollaborationInviteCodeStore()
    ) {
        self.defaults = defaults
        self.workspaceSessionBindingsKey = workspaceSessionBindingsKey
        self.inviteCodeStore = inviteCodeStore
    }

    /// Returns all valid workspace session bindings keyed by workspace ID.
    public func bindingsByWorkspaceID() -> [UUID: CollaborationWorkspaceSessionBinding] {
        guard let data = defaults.data(forKey: workspaceSessionBindingsKey) else { return [:] }
        guard let stored = try? JSONDecoder().decode([CollaborationWorkspaceSessionBinding].self, from: data) else {
            return [:]
        }
        return stored.reduce(into: [:]) { result, binding in
            let normalizedCode = inviteCodeStore.normalizedSessionCode(from: binding.sessionCode)
            guard !normalizedCode.isEmpty else { return }
            result[binding.workspaceID] = CollaborationWorkspaceSessionBinding(
                workspaceID: binding.workspaceID,
                sessionCode: normalizedCode
            )
        }
    }

    /// Returns the normalized session code assigned to a workspace, if any.
    /// - Parameter workspaceID: The workspace to query.
    /// - Returns: The normalized invite code for the workspace's session.
    public func sessionCode(forWorkspaceID workspaceID: UUID) -> String? {
        bindingsByWorkspaceID()[workspaceID]?.sessionCode
    }

    /// Assigns a workspace to a collaboration session.
    /// - Parameters:
    ///   - sessionCode: The invite code to assign.
    ///   - workspaceID: The workspace that owns the session.
    public func record(sessionCode: String, forWorkspaceID workspaceID: UUID) {
        let normalizedCode = inviteCodeStore.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        var bindings = bindingsByWorkspaceID()
        bindings[workspaceID] = CollaborationWorkspaceSessionBinding(
            workspaceID: workspaceID,
            sessionCode: normalizedCode
        )
        persist(bindings)
    }

    /// Removes the session binding for a workspace.
    /// - Parameter workspaceID: The workspace whose binding should be removed.
    public func remove(workspaceID: UUID) {
        var bindings = bindingsByWorkspaceID()
        bindings.removeValue(forKey: workspaceID)
        persist(bindings)
    }

    /// Removes every workspace session binding.
    public func removeAll() {
        defaults.removeObject(forKey: workspaceSessionBindingsKey)
    }

    private func persist(_ bindings: [UUID: CollaborationWorkspaceSessionBinding]) {
        let sorted = bindings.values.sorted {
            $0.workspaceID.uuidString < $1.workspaceID.uuidString
        }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: workspaceSessionBindingsKey)
    }
}
