/// Classifies a directory-join failure so the client can decide whether to prune
/// the stale invite locally. A "gone" failure means the session ended, was
/// withdrawn, or the descriptor is no longer valid; anything else is treated as
/// transient and the invite is kept.
public enum CollaborationInboxJoinFailure {
    /// Whether an HTTP join failure indicates the invite should be pruned.
    /// - Parameters:
    ///   - status: The HTTP status code from the join response.
    ///   - code: The optional machine-readable error code from the response body.
    public static func indicatesInviteGone(status: Int, code: String?) -> Bool {
        // 410 Gone = the relay room no longer exists; 403 = we are no longer
        // invited (withdrawn / consumed elsewhere).
        if status == 410 || status == 403 { return true }
        switch code {
        case "session_ended", "not_invited", "invalid_session":
            return true
        default:
            return false
        }
    }
}
