@MainActor
enum GhosttySurfaceConfigurationRefresh {
    nonisolated static let forceRefreshReason = "appDelegate.refreshAfterGhosttyConfigReload"
    nonisolated static let mosaicThemeReloadLegacySource = "distributed.mosaic.themes"
    nonisolated static let mosaicThemeReloadPreviewSource = "distributed.mosaic.themes.preview"
    nonisolated static let mosaicThemeReloadFinalSource = "distributed.mosaic.themes.final"
    nonisolated static let mosaicThemePreviewReloadDebounceMilliseconds = 180

    nonisolated static func mosaicThemeReloadSource(phase: String?) -> String {
        switch phase {
        case "final", "apply":
            return mosaicThemeReloadFinalSource
        case "preview":
            return mosaicThemeReloadPreviewSource
        default:
            return mosaicThemeReloadLegacySource
        }
    }

    nonisolated static func shouldDebounceMosaicThemeReload(source: String) -> Bool {
        switch source {
        case mosaicThemeReloadLegacySource, mosaicThemeReloadPreviewSource:
            return true
        default:
            return false
        }
    }

    nonisolated static func isMosaicThemeReloadSource(_ source: String) -> Bool {
        switch source {
        case mosaicThemeReloadLegacySource, mosaicThemeReloadPreviewSource, mosaicThemeReloadFinalSource:
            return true
        default:
            return false
        }
    }

    static func applyAfterAppConfigReload(
        to surface: ghostty_surface_t?,
        source: String,
        reloadSurfaceConfiguration: (ghostty_surface_t, Bool, String) -> Void,
        applySurfaceColorScheme: () -> Void,
        refreshHostBackground: () -> Void,
        forceRefresh: (String) -> Void
    ) {
        if let surface {
            applySurfaceColorScheme()
            reloadSurfaceConfiguration(surface, true, source)
        }
        refreshHostBackground()
        forceRefresh(forceRefreshReason)
    }
}
