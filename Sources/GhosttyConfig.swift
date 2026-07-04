import MosaicTerminalCore

/// App-target alias for ``MosaicTerminalCore/GhosttyConfig``, lifted into
/// MosaicTerminalCore in stack D tranche A. Keeps every `GhosttyConfig` call site
/// (and `GhosttyConfig.ColorSchemePreference` / `GhosttyConfig.UserAppearanceConfigSummary`
/// member lookups) byte-identical across the app target.
typealias GhosttyConfig = MosaicTerminalCore.GhosttyConfig
