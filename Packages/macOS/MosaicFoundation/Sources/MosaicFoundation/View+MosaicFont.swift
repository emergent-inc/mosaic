public import SwiftUI

/// Adds mosaic-owned font scaling modifiers to SwiftUI views.
public extension View {
    /// Injects the global font magnification percent into this view subtree.
    ///
    /// Apply this once near each mosaic-owned SwiftUI root. Descendant
    /// ``mosaicFont(size:weight:design:monospacedDigit:)`` calls then read the
    /// environment value without creating per-label `UserDefaults`
    /// subscriptions.
    ///
    /// - Returns: A view that supplies the current magnification percent to descendants.
    func mosaicFontMagnificationEnvironment() -> some View {
        modifier(MosaicFontMagnificationEnvironmentModifier())
    }

    /// Apply a system font at `size` points, scaled by the global magnification.
    ///
    /// - Parameters:
    ///   - size: The unscaled base point size.
    ///   - weight: The system font weight to apply.
    ///   - design: The system font design to apply.
    ///   - monospacedDigit: Whether numeric glyphs should use tabular widths.
    /// - Returns: A view with a magnification-aware system font.
    func mosaicFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(
            MosaicFontModifier(
                baseSize: size,
                weight: weight,
                design: design,
                monospacedDigit: monospacedDigit
            )
        )
    }

    /// Apply a text-style-sized system font, scaled by the global magnification.
    ///
    /// - Parameters:
    ///   - style: The SwiftUI text style whose mosaic base metrics should be used.
    ///   - weight: An optional weight override. When `nil`, mosaic uses the style's default weight.
    ///   - design: The system font design to apply.
    ///   - monospacedDigit: Whether numeric glyphs should use tabular widths.
    /// - Returns: A view with a magnification-aware font for the requested text style.
    func mosaicFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default,
        monospacedDigit: Bool = false
    ) -> some View {
        mosaicFont(
            size: MosaicTextStyleMetrics(style: style).baseSize,
            weight: weight ?? MosaicTextStyleMetrics(style: style).baseWeight,
            design: design,
            monospacedDigit: monospacedDigit
        )
    }
}
