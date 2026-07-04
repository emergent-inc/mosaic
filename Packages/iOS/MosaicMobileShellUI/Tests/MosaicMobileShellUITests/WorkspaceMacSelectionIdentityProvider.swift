import MosaicMobileShellModel

@MainActor
final class WorkspaceMacSelectionIdentityProvider: MobileIdentityProviding {
    var currentUserID: String?

    init(userID: String?) {
        self.currentUserID = userID
    }
}
