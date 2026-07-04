import Foundation

/// Runtime bridge between one sidebar extension instance and its XPC connection.
///
/// `@unchecked Sendable` is safe here because the only stored state is the
/// lock-protected `MosaicSidebarExtensionConnection`. The extension instance is
/// captured weakly inside `@MainActor` callbacks and is not stored on this type.
final class MosaicSidebarExtensionRuntime: @unchecked Sendable {
    private let connection: MosaicSidebarExtensionConnection

    @MainActor
    init<Extension: MosaicSidebarExtension>(sidebarExtension: Extension) {
        var transport: MosaicSidebarExtensionConnection!
        transport = MosaicSidebarExtensionConnection(
            manifest: Extension.manifest,
            onSnapshot: { [weak sidebarExtension] snapshot in
                let host = MosaicSidebarHost(
                    performCancellableAction: { action, reply in
                        transport.perform(action, reply: reply)
                    },
                    refreshSnapshot: {
                        transport.refreshSnapshot()
                    }
                )
                sidebarExtension?.update(context: MosaicSidebarContext(snapshot: snapshot, host: host))
            },
            onStatus: { [weak sidebarExtension] status in
                sidebarExtension?.connectionStatusDidChange(status)
            }
        )
        self.connection = transport
    }

    @discardableResult
    func accept(_ connection: NSXPCConnection) -> Bool {
        self.connection.accept(connection)
    }

    deinit {
        connection.invalidate()
    }
}
