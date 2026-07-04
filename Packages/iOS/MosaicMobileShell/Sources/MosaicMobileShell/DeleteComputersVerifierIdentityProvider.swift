#if DEBUG
import MosaicMobileShellModel

@MainActor
final class DeleteComputersVerifierIdentityProvider: MobileIdentityProviding {
    let currentUserID: String?

    init(userID: String?) {
        currentUserID = userID
    }
}
#endif
