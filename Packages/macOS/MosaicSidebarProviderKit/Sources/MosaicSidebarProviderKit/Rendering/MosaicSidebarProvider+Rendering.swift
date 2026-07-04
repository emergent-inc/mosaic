import Foundation

public extension MosaicSidebarProvider {
    /// Builds the default empty render model for providers that do not implement rendering.
    func render(snapshot: MosaicSidebarProviderSnapshot) -> MosaicSidebarProviderRenderModel {
        MosaicSidebarProviderRenderModel(
            providerId: descriptor.id,
            snapshotSequence: snapshot.sequence,
            sections: []
        )
    }

    /// Builds a render model using contextual rendering when available.
    func render(
        snapshot: MosaicSidebarProviderSnapshot,
        context: MosaicSidebarProviderRenderContext
    ) -> MosaicSidebarProviderRenderModel {
        render(snapshot: snapshot)
    }
}
