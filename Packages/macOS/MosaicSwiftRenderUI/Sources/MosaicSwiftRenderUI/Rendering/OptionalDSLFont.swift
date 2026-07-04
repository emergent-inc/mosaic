import MosaicFoundation
import SwiftUI

struct OptionalDSLFont: ViewModifier {
    let spec: DSLFontSpec?

    func body(content: Content) -> some View {
        if let spec {
            content.mosaicFont(
                size: spec.baseSize,
                weight: spec.weight ?? .regular,
                design: spec.design
            )
        } else {
            content
        }
    }
}
