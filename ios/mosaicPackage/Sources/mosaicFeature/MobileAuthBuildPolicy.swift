import Foundation

/// Build-time auth policy flags resolved from the active compilation flags.
///
/// A value type (not a static namespace) so the composition root reads it once
/// and threads the result into ``MosaicAuthRuntime/AuthLaunchOptions``.
public struct MobileAuthBuildPolicy: Sendable {
    /// Whether this build includes the debug `42` sign-in shortcut + persisted
    /// debug credentials. True only on `MOSAIC_DEV_AUTH` (DEBUG) builds.
    public let includesFortyTwoShortcut: Bool

    /// The build policy for the current compilation.
    public static var current: MobileAuthBuildPolicy {
        #if MOSAIC_DEV_AUTH
        MobileAuthBuildPolicy(includesFortyTwoShortcut: true)
        #else
        MobileAuthBuildPolicy(includesFortyTwoShortcut: false)
        #endif
    }

    /// Creates a build policy.
    public init(includesFortyTwoShortcut: Bool) {
        self.includesFortyTwoShortcut = includesFortyTwoShortcut
    }
}
