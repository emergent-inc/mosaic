import AppKit
import CMUXMobileCore
import CmuxWorkspaces
import CmuxSettingsUI
import CmuxFoundation
import Foundation
import OSLog
import SwiftUI

private let hostSettingsLogger = Logger(subsystem: "com.cmuxterm.app", category: "Settings")

/// App-side implementation of the package's `SettingsHostActions`
/// protocol. Routes UI-triggered actions to the existing host
/// services (`BrowserHistoryStore`, `BrowserDataImportCoordinator`,
/// `TerminalNotificationStore`, etc.) so the package doesn't need to
/// depend on them directly.
@MainActor
final class HostSettingsActions: SettingsHostActions {
    private let configFileURL: URL

    /// Serializes font-size config writes so rapid slider saves persist in order.
    private let fontConfigWriter = FontConfigWriter()

    /// AppKit window identifier the dedicated terminal-config window carries.
    /// Matches the value `ConfigSettingsView.configureWindow` assigns so the
    /// host reuses a config window opened from any entrypoint (the legacy
    /// in-app button's SwiftUI scene or this host-presented window).
    private let configWindowIdentifier = "cmux.configEditor"

    /// Observes the `appIconMode` defaults key the settings package writes
    /// so the host can re-apply the dock/app-switcher icon when the user
    /// changes the App Icon picker. The package only persists the value;
    /// applying `NSApplication.shared.applicationIconImage` is host work.
    ///
    /// Uses the closure-based `NSKeyValueObservation` token API, the
    /// sanctioned seam for bridging a Foundation type that exposes change
    /// only via KVO (`UserDefaults`). The token is invalidated in `deinit`.
    private var appIconModeObservation: NSKeyValueObservation?

    /// Retains the AppKit window hosting ``ConfigSettingsView`` so repeated
    /// "Open Config" presses reuse the same dedicated terminal-config
    /// window instead of stacking duplicates.
    private var configWindow: NSWindow?
    private var configWindowCloseObserver: WindowCloseObserver?

    init(configFileURL: URL) {
        self.configFileURL = configFileURL
        startObservingAppIconMode()
    }

    deinit {
        appIconModeObservation?.invalidate()
    }

    private func trackSettingsAction(
        _ actionID: String,
        properties: [String: Any] = [:]
    ) {
        PostHogAnalytics.shared.trackAction(
            actionID: actionID,
            surface: "settings",
            entrypoint: "settings_host_actions",
            source: "HostSettingsActions",
            properties: properties
        )
        PostHogAnalytics.shared.capture(
            .buttonClicked,
            properties: ([
                "action_id": actionID,
                "surface": "settings",
                "entrypoint": "settings_host_actions",
            ] as [String: Any]).merging(properties) { current, _ in current }
        )
    }

    private func startObservingAppIconMode() {
        // Apply once on construction so a value persisted before this
        // instance existed (e.g. from the config file) is reflected.
        AppIconSettings.applyIcon(AppIconSettings.resolvedMode())

        appIconModeObservation = UserDefaults.standard.observe(
            \.appIconMode,
            options: [.new]
        ) { _, _ in
            // KVO delivers on the thread that mutated the key; @AppStorage
            // writes happen on the main actor, so hop to it to apply.
            Task { @MainActor in
                AppIconSettings.applyIcon(AppIconSettings.resolvedMode())
            }
        }
    }

    func clearBrowserHistory() {
        trackSettingsAction("settings.clear_browser_history")
        BrowserHistoryStore.shared.clearHistory()
    }

    func sleepyModePreview() {
        trackSettingsAction("settings.sleepy_mode_preview")
        SleepyModeController.shared.preview()
    }

    func sleepyModeStart() {
        trackSettingsAction("settings.sleepy_mode_start")
        SleepyModeController.shared.activate()
    }

    func sleepyModeStore() -> SleepyModeSettingsStore {
        SleepyModeController.shared.store
    }

    func openConfigInExternalEditor() {
        trackSettingsAction("settings.open_config_external_editor")
        // Honor the user's configured editor (`preferredEditorCommand`),
        // falling back to the OS default. Opening the config file directly
        // through `NSWorkspace.shared.open` would route to the default
        // `.json` handler and ignore the cmux setting.
        PreferredEditorService(defaults: .standard).open(configFileURL)
    }

    func sendFeedback() {
        trackSettingsAction("settings.send_feedback")
        guard let url = URL(string: "https://github.com/emergent-inc/mosaic/issues/new") else { return }
        NSWorkspace.shared.open(url)
    }

    func sendTestNotification() {
        trackSettingsAction("settings.send_test_notification")
        TerminalNotificationStore.shared.sendSettingsTestNotification()
    }

    func openSystemNotificationSettings() {
        trackSettingsAction("settings.open_system_notification_settings")
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    func restartApp() {
        trackSettingsAction("settings.restart_app")
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    func openBrowserImportFlow() {
        trackSettingsAction("settings.open_browser_import_flow")
        BrowserDataImportCoordinator.shared.presentImportDialog()
    }

    func requestNotificationAuthorization() {
        trackSettingsAction("settings.request_notification_authorization")
        TerminalNotificationStore.shared.requestAuthorizationFromSettings()
    }

    func openTerminalConfigWindow() {
        trackSettingsAction("settings.open_terminal_config_window")
        NSApp.activate(ignoringOtherApps: true)

        // Legacy opened the dedicated config window via the SwiftUI
        // `openWindow(id: ConfigSettingsView.windowID)` environment. The
        // settings package can't reach that environment, so the host opens
        // the same `ConfigSettingsView` directly. Reuse the existing window
        // (identifier set by `ConfigSettingsView.configureWindow`) when one
        // is already open so repeated presses focus instead of duplicate.
        if let existing = existingConfigWindow() {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        let appearanceMode = UserDefaults.standard.string(forKey: AppearanceSettings.appearanceModeKey)
        let root = ConfigSettingsView()
            .cmuxAppearanceColorScheme(appearanceMode)
        let hostingController = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "settings.config.windowTitle", defaultValue: "Config")
        window.identifier = NSUserInterfaceItemIdentifier(configWindowIdentifier)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 980, height: 680))
        window.center()
        configWindow = window
        configWindowCloseObserver = WindowCloseObserver(window: window) { [weak self] in
            self?.releaseConfigWindow($0)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func setMenuBarOnly(_ enabled: Bool) -> Bool {
        trackSettingsAction("settings.set_menu_bar_only", properties: ["enabled": enabled])
        MenuBarOnlySettings.setEnabled(enabled)
        return true
    }

    func openMobilePairingWindow() {
        trackSettingsAction("settings.open_mobile_pairing_window")
        MobilePairingWindowController.shared.show()
    }

    private func existingConfigWindow() -> NSWindow? {
        if let configWindow, configWindow.isVisible || configWindow.isMiniaturized {
            return configWindow
        }
        return NSApp.windows.first {
            $0.identifier?.rawValue == configWindowIdentifier && ($0.isVisible || $0.isMiniaturized)
        }
    }

    private func releaseConfigWindow(_ window: NSWindow) {
        guard configWindow === window else { return }
        configWindowCloseObserver = nil
        window.contentView = nil
        window.contentViewController = nil
        configWindow = nil
    }

    func previewNotificationSound(value: String, customFilePath: String) {
        trackSettingsAction("settings.preview_notification_sound")
        NotificationSoundSettings.previewSound(value: value, customFilePath: customFilePath)
    }

    func browserHistoryEntryCount() -> Int? {
        guard BrowserHistoryStore.shared.isLoaded else { return nil }
        return BrowserHistoryStore.shared.entries.count
    }

    func sidebarFontSize() -> SettingsFontSize {
        // Reads the in-memory cache (kept current by config reloads) rather than
        // forcing a synchronous disk read on the main actor when Settings opens.
        SettingsFontSize(
            points: Double(GhosttyConfig.load().sidebarFontSize),
            minimum: CmuxGhosttyConfigSettingEditor.minSidebarFontSize,
            maximum: CmuxGhosttyConfigSettingEditor.maxSidebarFontSize,
            defaultValue: CmuxGhosttyConfigSettingEditor.defaultSidebarFontSize
        )
    }

    func setSidebarFontSize(_ points: Double) async -> Bool {
        let didPersist = await persistFontSize(
            key: CmuxGhosttyConfigSettingEditor.sidebarFontSizeKey,
            points: CmuxGhosttyConfigSettingEditor().clampedSidebarFontSize(points),
            reloadSource: "settings.sidebar.fontSize"
        )
        if didPersist {
            trackSettingsAction("settings.set_sidebar_font_size")
        }
        return didPersist
    }

    func surfaceTabBarFontSize() -> SettingsFontSize {
        // See ``sidebarFontSize()`` — uses the cached config to avoid main-actor disk I/O.
        SettingsFontSize(
            points: Double(GhosttyConfig.load().surfaceTabBarFontSize),
            minimum: CmuxGhosttyConfigSettingEditor.minSurfaceTabBarFontSize,
            maximum: CmuxGhosttyConfigSettingEditor.maxSurfaceTabBarFontSize,
            defaultValue: CmuxGhosttyConfigSettingEditor.defaultSurfaceTabBarFontSize
        )
    }

    func setSurfaceTabBarFontSize(_ points: Double) async -> Bool {
        let didPersist = await persistFontSize(
            key: CmuxGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey,
            points: CmuxGhosttyConfigSettingEditor().clampedSurfaceTabBarFontSize(points),
            reloadSource: "settings.terminal.tabBarFontSize"
        )
        if didPersist {
            trackSettingsAction("settings.set_surface_tab_bar_font_size")
        }
        return didPersist
    }

    func formattedFontSize(_ points: Double) -> String {
        CmuxGhosttyConfigSettingEditor().formattedFontSize(points)
    }

    func mobilePairingStatus() -> MobilePairingStatusSnapshot? {
        Self.mobilePairingSnapshot(from: MobileHostService.shared.statusSnapshot())
    }

    func mobilePairingStatusUpdates() -> AsyncStream<MobilePairingStatusSnapshot> {
        AsyncStream { continuation in
            // Bridge the notification through a Sendable `Void` signal stream so
            // the non-Sendable `Notification` never crosses into the MainActor
            // drain task. Mirrors `UserDefaultsSettingsStore.values(for:)`.
            let (signals, signalContinuation) = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            let observer = MobileHostStatusObserverToken(
                NotificationCenter.default.addObserver(
                    forName: .mobileHostStatusDidChange,
                    object: nil,
                    queue: nil
                ) { _ in
                    signalContinuation.yield(())
                }
            )
            let drainTask = Task { @MainActor in
                // Seed with the current status, then forward every change.
                continuation.yield(Self.mobilePairingSnapshot(from: MobileHostService.shared.statusSnapshot()))
                for await _ in signals {
                    if Task.isCancelled { break }
                    continuation.yield(Self.mobilePairingSnapshot(from: MobileHostService.shared.statusSnapshot()))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                drainTask.cancel()
                signalContinuation.finish()
                observer.remove()
            }
        }
    }

    /// Maps the host's ``MobileHostServiceStatus`` into the settings package's
    /// Foundation-only ``MobilePairingStatusSnapshot``. Static so the status
    /// stream's forwarding task does not retain this host bridge.
    private static func mobilePairingSnapshot(from status: MobileHostServiceStatus) -> MobilePairingStatusSnapshot {
        let routes = status.routes.compactMap { route -> MobilePairingRoute? in
            guard case let .hostPort(host, port) = route.endpoint else { return nil }
            return MobilePairingRoute(
                id: route.id,
                kindLabel: routeKindLabel(route.kind),
                host: host,
                port: port
            )
        }
        return MobilePairingStatusSnapshot(
            isRunning: status.isRunning,
            configuredPort: status.configuredPort,
            boundPort: status.port,
            usesEphemeralFallback: status.usesEphemeralFallback,
            activeConnectionCount: status.activeConnectionCount,
            routes: routes
        )
    }

    func mobilePairingDefaultDisplayName() -> String {
        // The Mac's system name, the pairing name used when no override is set.
        // Stable across override edits, so the placeholder never goes stale.
        Host.current().localizedName ?? ""
    }

    func applyMobilePairingPort(_ port: Int) async -> MobilePairingPortApplyResult {
        switch await MobileHostService.shared.applyConfiguredPort(port) {
        case .applied(let bound):
            trackSettingsAction("settings.mobile_pairing_port_applied")
            return .applied(port: bound)
        case .portInUse:
            trackSettingsAction("settings.mobile_pairing_port_failed", properties: ["result": "port_in_use"])
            return .portInUse(requestedPort: port)
        case .savedWhileDisabled:
            trackSettingsAction("settings.mobile_pairing_port_saved_for_later")
            return .savedForLater(port: port)
        case .invalid:
            trackSettingsAction("settings.mobile_pairing_port_failed", properties: ["result": "invalid"])
            return .invalid(requestedPort: port)
        }
    }

    /// Localized transport label for a pairing route shown in diagnostics.
    private static func routeKindLabel(_ kind: CmxAttachTransportKind) -> String {
        switch kind {
        case .tailscale:
            return String(localized: "settings.mobile.route.tailscale", defaultValue: "Tailscale")
        case .debugLoopback:
            return String(localized: "settings.mobile.route.loopback", defaultValue: "Loopback")
        case .iroh:
            return String(localized: "settings.mobile.route.iroh", defaultValue: "Iroh")
        case .websocket:
            return String(localized: "settings.mobile.route.websocket", defaultValue: "WebSocket")
        }
    }

    /// Writes a clamped font-size value to cmux's editable Ghostty config and
    /// triggers a live reload so open windows re-render at the new size.
    ///
    /// The disk write runs on the serial ``fontConfigWriter`` actor so the main
    /// actor is never blocked on file I/O during a slider drag or Reset tap, and
    /// rapid successive saves persist in submission order (last value wins). The
    /// reload then resumes on the main actor.
    ///
    /// - Returns: `true` on success, `false` if the write failed (a generic
    ///   warning is logged here; the Settings UI surfaces a save-failed message).
    private func persistFontSize(key: String, points: Double, reloadSource: String) async -> Bool {
        let formatted = CmuxGhosttyConfigSettingEditor().formattedFontSize(points)
        guard await fontConfigWriter.write(key: key, value: formatted) else {
            hostSettingsLogger.warning("failed to persist \(key, privacy: .public)")
            return false
        }
        GhosttyApp.shared.reloadConfiguration(source: reloadSource)
        return true
    }

}

/// Wraps the opaque observer returned by `NotificationCenter.addObserver` so the
/// `@Sendable` stream-termination closure can hold it for removal. Objective-C
/// doesn't model `Sendable`; the token is immutable and only hands the opaque
/// observer back to NotificationCenter's thread-safe removal API. CmuxSettings
/// has an identical internal token, which isn't `public`, so it's duplicated.
final class MobileHostStatusObserverToken: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    func remove() {
        NotificationCenter.default.removeObserver(token)
    }
}

/// Serializes cmux Ghostty config writes for the font-size settings so rapid
/// successive saves apply in submission order instead of racing.
///
/// The Settings sliders fire a save on every release and Reset tap. Routed
/// through this single actor, the writes run one-at-a-time in arrival order —
/// each write is a full overwrite of the key, so the most recently submitted
/// value is always the one left on disk. The work runs off the main actor.
private actor FontConfigWriter {
    /// Writes a single cmux-editable Ghostty config setting to disk.
    ///
    /// - Parameters:
    ///   - key: The Ghostty config key to write (e.g. `sidebar-font-size`).
    ///   - value: The already-formatted value to persist.
    /// - Returns: `true` if the write succeeded, `false` otherwise.
    func write(key: String, value: String) -> Bool {
        do {
            try ConfigSourceEnvironment.live().writeCmuxConfigSetting(key: key, value: value)
            return true
        } catch {
            return false
        }
    }
}

private extension UserDefaults {
    /// KVO-observable accessor for the `appIconMode` defaults key.
    ///
    /// `UserDefaults` is KVO-compliant for any key accessed through a
    /// matching `@objc dynamic` property whose name equals the key, which
    /// lets ``HostSettingsActions`` observe App Icon changes the settings
    /// package writes via `@AppStorage`. The property name must stay equal
    /// to ``AppIconSettings/modeKey`` (`"appIconMode"`).
    @objc dynamic var appIconMode: String? {
        string(forKey: "appIconMode")
    }
}
