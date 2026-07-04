public import SwiftUI

/// Injects the stored mosaic font magnification percent into a SwiftUI subtree.
struct MosaicFontMagnificationEnvironmentModifier: ViewModifier {
    @AppStorage(GlobalFontMagnification.percentKey) private var percent = GlobalFontMagnification.defaultPercent

    func body(content: Content) -> some View {
        content.environment(\.mosaicGlobalFontMagnificationPercent, percent)
    }
}
