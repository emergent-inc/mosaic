import SwiftUI

/// Stores the current global font magnification percent in the SwiftUI environment.
struct MosaicGlobalFontMagnificationPercentKey: EnvironmentKey {
    static var defaultValue: Int { GlobalFontMagnification.storedPercent }
}
