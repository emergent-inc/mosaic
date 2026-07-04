public import SwiftUI

/// Adds mosaic font magnification values to SwiftUI environment lookups.
public extension EnvironmentValues {
    /// The current clamped global font magnification percent.
    ///
    /// mosaic scene roots should inject this value with
    /// ``View/mosaicFontMagnificationEnvironment()`` so repeated row labels can
    /// read a pure environment value instead of each subscribing to
    /// `UserDefaults`.
    var mosaicGlobalFontMagnificationPercent: Int {
        get { self[MosaicGlobalFontMagnificationPercentKey.self] }
        set { self[MosaicGlobalFontMagnificationPercentKey.self] = GlobalFontMagnification.clamp(newValue) }
    }
}
