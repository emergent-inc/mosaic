import Foundation

/// Provider that can both render sidebar state and handle host mutations.
public protocol MosaicMutableSidebarProvider: MosaicContextualSidebarProvider {
    /// Handles a mutation against the latest sidebar snapshot.
    func handle(
        _ mutation: MosaicSidebarProviderMutation,
        snapshot: MosaicSidebarProviderSnapshot
    ) throws -> MosaicSidebarProviderCommandResult
}
