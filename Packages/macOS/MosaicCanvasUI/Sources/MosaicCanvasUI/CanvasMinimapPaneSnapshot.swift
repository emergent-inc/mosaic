import CoreGraphics
import MosaicCanvas

/// One pane shown in the canvas minimap, in z-order.
struct CanvasMinimapPaneSnapshot: Equatable {
    let id: CanvasPaneID
    let frame: CGRect
}
