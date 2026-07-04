import Foundation

/// In-process sidebar provider used by MOSAIC-owned sidebar presentations.
public protocol MosaicSidebarProvider: Sendable {
    /// Stable metadata describing the provider in selection UI.
    var descriptor: MosaicSidebarProviderDescriptor { get }

    /// Builds a render model from the latest sidebar snapshot.
    func render(snapshot: MosaicSidebarProviderSnapshot) -> MosaicSidebarProviderRenderModel
}
