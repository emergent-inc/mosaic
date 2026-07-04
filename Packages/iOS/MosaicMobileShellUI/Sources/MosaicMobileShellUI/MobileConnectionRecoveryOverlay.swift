import MosaicMobileShell
import SwiftUI

private struct MobileConnectionRecoveryOverlay: ViewModifier {
    @Bindable var store: MosaicMobileShellStore
    var signOut: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            MobileConnectionRecoveryBanner(
                connectionRequiresReauth: store.connectionRequiresReauth,
                connectionRecoveryFailed: store.connectionRecoveryFailed,
                isRecoveringConnection: store.isRecoveringConnection,
                connectionError: store.connectionError,
                retry: { store.retryMobileConnection() },
                signOut: signOut
            )
        }
    }
}

extension View {
    func mobileConnectionRecoveryOverlay(
        store: MosaicMobileShellStore,
        signOut: (() -> Void)?
    ) -> some View {
        modifier(MobileConnectionRecoveryOverlay(store: store, signOut: signOut))
    }
}
