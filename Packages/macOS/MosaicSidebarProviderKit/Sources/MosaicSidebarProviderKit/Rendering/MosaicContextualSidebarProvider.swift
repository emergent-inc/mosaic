import Foundation

/// Provider that renders with explicit render context.
public protocol MosaicContextualSidebarProvider: MosaicSidebarProvider {
    /// Builds a render model from a sidebar snapshot and render context.
    func render(snapshot: MosaicSidebarProviderSnapshot, context: MosaicSidebarProviderRenderContext) -> MosaicSidebarProviderRenderModel
}
