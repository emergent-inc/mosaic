import XCTest
import AppKit
// Selective imports: the app target also defines AppIconMode/StoredShortcut/etc.,
// so a blanket `import MosaicSettings` here makes those names ambiguous. Import only
// the settings symbols this file needs.
import struct MosaicSettings.AppCatalogSection
import struct MosaicSettings.QuitConfirmationStore
import enum MosaicSettings.ConfirmQuitMode
import enum MosaicSettings.BrowserSearchEngine
import struct MosaicSettings.BrowserSearchSettingsStore

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

final class KeyboardShortcutSettingsFileStoreStartupTests: XCTestCase {
    private var originalSettingsFileStore: KeyboardShortcutSettingsFileStore!
    private let settingsFileBackupsDefaultsKey = "mosaic.settingsFile.backups.v1"
    private let importedManagedDefaultsKey = "mosaic.settingsFile.importedManagedDefaults.v1"

    override func setUp() {
        super.setUp()
        originalSettingsFileStore = KeyboardShortcutSettings.settingsFileStore
        KeyboardShortcutSettings.resetAll()
    }

    override func tearDown() {
        KeyboardShortcutSettings.settingsFileStore = originalSettingsFileStore
        AppIconSettings.resetLiveEnvironmentProviderForTesting()
        KeyboardShortcutSettings.resetAll()
        super.tearDown()
    }

    func testSettingsFileStoreParsesNumberedShortcutWithoutConsultingActiveShortcutStore() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let activeSettingsFileURL = directoryURL.appendingPathComponent("active.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "shortcuts": {
                "openBrowser": "cmd+3"
              }
            }
            """,
            to: activeSettingsFileURL
        )

        KeyboardShortcutSettings.settingsFileStore = KeyboardShortcutSettingsFileStore(
            primaryPath: activeSettingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )
        XCTAssertEqual(
            KeyboardShortcutSettings.shortcut(for: .openBrowser),
            StoredShortcut(key: "3", command: true, shift: false, option: false, control: false)
        )

        let parsedSettingsFileURL = directoryURL.appendingPathComponent("parsed.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "shortcuts": {
                "selectWorkspaceByNumber": "cmd+7"
              }
            }
            """,
            to: parsedSettingsFileURL
        )

        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: parsedSettingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(
            store.override(for: .selectWorkspaceByNumber),
            StoredShortcut(key: "1", command: true, shift: false, option: false, control: false)
        )
    }

    func testSettingsFileShortcutNormalizationAcceptsRecorderConflictingShortcut() {
        KeyboardShortcutSettings.resetAll()
        defer { KeyboardShortcutSettings.resetAll() }

        let shortcut = StoredShortcut(key: "t", command: true, shift: false, option: false, control: false)

        XCTAssertEqual(
            KeyboardShortcutSettings.Action.openBrowser.normalizedSettingsFileShortcut(shortcut),
            shortcut
        )
    }

    func testSettingsFileStoreRestoresAbsentAppIconBackupDuringStartupWithoutTouchingAppKit() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: AppIconSettings.modeKey)
        let previousBackups = defaults.data(forKey: settingsFileBackupsDefaultsKey)
        let previousImportedDefaults = defaults.data(forKey: importedManagedDefaultsKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppIconSettings.modeKey)
            } else {
                defaults.removeObject(forKey: AppIconSettings.modeKey)
            }

            if let previousBackups {
                defaults.set(previousBackups, forKey: settingsFileBackupsDefaultsKey)
            } else {
                defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            }
            if let previousImportedDefaults {
                defaults.set(previousImportedDefaults, forKey: importedManagedDefaultsKey)
            } else {
                defaults.removeObject(forKey: importedManagedDefaultsKey)
            }
        }

        defaults.removeObject(forKey: AppIconSettings.modeKey)
        defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
        defaults.removeObject(forKey: importedManagedDefaultsKey)

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let managedIconURL = directoryURL.appendingPathComponent("icon.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "app": {
                "appIcon": "automatic"
              }
            }
            """,
            to: managedIconURL
        )

        var startObservationCallCount = 0
        var stopObservationCallCount = 0
        var imageRequestCount = 0
        var runtimeIconSetCount = 0
        var dockTileNotificationCount = 0
        AppIconSettings.setLiveEnvironmentProviderForTesting {
            AppIconSettings.Environment(
                isApplicationFinishedLaunching: { false },
                imageForMode: { _ in
                    imageRequestCount += 1
                    return nil
                },
                setApplicationIconImage: { _ in
                    runtimeIconSetCount += 1
                },
                startAppearanceObservation: {
                    startObservationCallCount += 1
                },
                stopAppearanceObservation: {
                    stopObservationCallCount += 1
                },
                notifyDockTilePlugin: {
                    dockTileNotificationCount += 1
                }
            )
        }

        _ = KeyboardShortcutSettingsFileStore(
            primaryPath: managedIconURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(defaults.string(forKey: AppIconSettings.modeKey), AppIconMode.automatic.rawValue)

        let emptyManagedURL = directoryURL.appendingPathComponent("empty.json", isDirectory: false)
        try writeSettingsFile("{}", to: emptyManagedURL)

        _ = KeyboardShortcutSettingsFileStore(
            primaryPath: emptyManagedURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertNil(defaults.object(forKey: AppIconSettings.modeKey))
        XCTAssertEqual(startObservationCallCount, 0)
        XCTAssertEqual(stopObservationCallCount, 0)
        XCTAssertEqual(imageRequestCount, 0)
        XCTAssertEqual(runtimeIconSetCount, 0)
        XCTAssertEqual(dockTileNotificationCount, 0)
    }

    /// mosaic pins a fixed dark appearance; a leftover `app.appearance` key in
    /// mosaic.json must be silently ignored (no managed default written and no
    /// parse abort for the rest of the `app` section).
    func testLegacyAppearanceKeyInConfigIsIgnored() throws {
        let defaults = UserDefaults.standard
        let legacyAppearanceModeKey = "appearanceMode"

        try preservingDefaults(keys: [
            legacyAppearanceModeKey,
            AppCatalogSection().warnBeforeQuit.userDefaultsKey,
            AppCatalogSection().confirmQuitMode.userDefaultsKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: legacyAppearanceModeKey)
            defaults.removeObject(forKey: AppCatalogSection().warnBeforeQuit.userDefaultsKey)
            defaults.removeObject(forKey: AppCatalogSection().confirmQuitMode.userDefaultsKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "appearance": "light",
                    "warnBeforeQuit": false
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertNil(defaults.object(forKey: legacyAppearanceModeKey))
            XCTAssertEqual(
                defaults.object(forKey: AppCatalogSection().warnBeforeQuit.userDefaultsKey) as? Bool,
                false
            )
        }
    }

    func testSidebarMatchTerminalBackgroundUserDefaultSurvivesSettingsFileReapply() throws {
        let defaults = UserDefaults.standard
        let key = SidebarMatchTerminalBackgroundSettings.userDefaultsKey
        let previousValue = defaults.object(forKey: key)
        let previousBackups = defaults.data(forKey: settingsFileBackupsDefaultsKey)
        let previousImportedDefaults = defaults.data(forKey: importedManagedDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }

            if let previousBackups {
                defaults.set(previousBackups, forKey: settingsFileBackupsDefaultsKey)
            } else {
                defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            }
            if let previousImportedDefaults {
                defaults.set(previousImportedDefaults, forKey: importedManagedDefaultsKey)
            } else {
                defaults.removeObject(forKey: importedManagedDefaultsKey)
            }
        }

        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
        defaults.removeObject(forKey: importedManagedDefaultsKey)

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "sidebarAppearance": {
                "matchTerminalBackground": true
              }
            }
            """,
            to: settingsFileURL
        )

        let notificationCenter = NotificationCenter()
        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            notificationCenter: notificationCenter,
            startWatching: true
        )

        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)

        defaults.set(false, forKey: key)
        try withExtendedLifetime(store) {
            notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

            _ = KeyboardShortcutSettingsFileStore(primaryPath: settingsFileURL.path, fallbackPath: nil, additionalFallbackPaths: [], startWatching: false)
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

            try writeSettingsFile(
                """
                {
                  "sidebarAppearance": {
                    "matchTerminalBackground": false
                  }
                }
                """,
                to: settingsFileURL
            )
            store.reload()
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

            defaults.set(true, forKey: key)
            notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
        }
    }

    func testSettingsFileParsesMarkdownTypographyDefaults() throws {
        let defaults = UserDefaults.standard

        try preservingDefaults(keys: [
            MarkdownFontSizeSettings.key,
            MarkdownFontFamily.key,
            MarkdownMaxWidthSettings.key,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey
        ]) {
            defaults.removeObject(forKey: MarkdownFontSizeSettings.key)
            defaults.removeObject(forKey: MarkdownFontFamily.key)
            defaults.removeObject(forKey: MarkdownMaxWidthSettings.key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "markdown": {
                    "fontSize": 22,
                    "fontFamily": "  Avenir Next  \\n",
                    "maxWidth": 1220
                  }
                }
                """,
                to: settingsFileURL
            )

            let store = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            withExtendedLifetime(store) {
                XCTAssertEqual(defaults.integer(forKey: MarkdownFontSizeSettings.key), 22)
                XCTAssertEqual(defaults.string(forKey: MarkdownFontFamily.key), "Avenir Next")
                XCTAssertEqual(defaults.integer(forKey: MarkdownMaxWidthSettings.key), 1220)
            }
        }
    }

    func testSettingsFileParsesFileEditorWordWrap() throws {
        let defaults = UserDefaults.standard

        try preservingDefaults(keys: [
            FilePreviewWordWrapSettings.key,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey
        ]) {
            defaults.removeObject(forKey: FilePreviewWordWrapSettings.key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            // Defaults to off until the config opts in.
            XCTAssertFalse(FilePreviewWordWrapSettings.isEnabled(defaults: defaults))

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "fileEditor": {
                    "wordWrap": true
                  }
                }
                """,
                to: settingsFileURL
            )

            let store = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            withExtendedLifetime(store) {
                XCTAssertTrue(defaults.bool(forKey: FilePreviewWordWrapSettings.key))
                XCTAssertTrue(FilePreviewWordWrapSettings.isEnabled(defaults: defaults))
            }
        }
    }

    func testManagedBoolUserDefaultSurvivesSettingsFileReapplyUntilFileChanges() throws {
        let defaults = UserDefaults.standard
        let key = AppCatalogSection().warnBeforeQuit.userDefaultsKey

        try preservingDefaults(keys: [key, settingsFileBackupsDefaultsKey, importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "warnBeforeQuit": true
                  }
                }
                """,
                to: settingsFileURL
            )

            let notificationCenter = NotificationCenter()
            let store = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                notificationCenter: notificationCenter,
                startWatching: true
            )

            XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)

            defaults.set(false, forKey: key)
            try withExtendedLifetime(store) {
                notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)
                XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

                try writeSettingsFile(
                    """
                    {
                      "app": {
                        "warnBeforeQuit": false
                      }
                    }
                    """,
                    to: settingsFileURL
                )
                defaults.set(true, forKey: key)
                XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)

                store.reload()
                XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

                defaults.set(true, forKey: key)
                notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)
                XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
            }
        }
    }

    func testConfirmQuitImportsEnumFromMosaicJSON() throws {
        let defaults = UserDefaults.standard
        let key = AppCatalogSection().confirmQuitMode.userDefaultsKey

        try preservingDefaults(keys: [key, settingsFileBackupsDefaultsKey, importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "confirmQuit": "dirty-only"
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.string(forKey: key), ConfirmQuitMode.dirtyOnly.rawValue)
            XCTAssertEqual(QuitConfirmationStore(defaults: defaults).confirmQuitMode, .dirtyOnly)
        }
    }

    func testLegacyWarnBeforeQuitMapsToConfirmQuitWhenConfirmQuitIsAbsent() throws {
        let defaults = UserDefaults.standard
        let confirmQuitKey = AppCatalogSection().confirmQuitMode.userDefaultsKey
        let warnBeforeQuitKey = AppCatalogSection().warnBeforeQuit.userDefaultsKey

        try preservingDefaults(keys: [
            confirmQuitKey,
            warnBeforeQuitKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.set(ConfirmQuitMode.always.rawValue, forKey: confirmQuitKey)
            defaults.removeObject(forKey: warnBeforeQuitKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "warnBeforeQuit": false
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.string(forKey: confirmQuitKey), ConfirmQuitMode.never.rawValue)
            XCTAssertEqual(defaults.object(forKey: warnBeforeQuitKey) as? Bool, false)
            XCTAssertEqual(QuitConfirmationStore(defaults: defaults).confirmQuitMode, .never)
        }
    }

    func testLegacyWarnBeforeQuitMigrationPreservesUserOverride() throws {
        let defaults = UserDefaults.standard
        let confirmQuitKey = AppCatalogSection().confirmQuitMode.userDefaultsKey
        let warnBeforeQuitKey = AppCatalogSection().warnBeforeQuit.userDefaultsKey

        try preservingDefaults(keys: [
            confirmQuitKey,
            warnBeforeQuitKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: confirmQuitKey)
            defaults.set(true, forKey: warnBeforeQuitKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.set(
                Data(#"{"warnBeforeQuitShortcut":{"bool":{"_0":false}}}"#.utf8),
                forKey: importedManagedDefaultsKey
            )

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "warnBeforeQuit": false
                  }
                }
                """,
                to: settingsFileURL
            )

            let store = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertNil(defaults.string(forKey: confirmQuitKey))
            XCTAssertEqual(defaults.object(forKey: warnBeforeQuitKey) as? Bool, true)
            XCTAssertEqual(QuitConfirmationStore(defaults: defaults).confirmQuitMode, .always)

            try writeSettingsFile("{}", to: settingsFileURL)
            store.reload()

            XCTAssertNil(defaults.string(forKey: confirmQuitKey))
            XCTAssertEqual(defaults.object(forKey: warnBeforeQuitKey) as? Bool, true)
            XCTAssertEqual(QuitConfirmationStore(defaults: defaults).confirmQuitMode, .always)
        }
    }

    func testInvalidConfirmQuitDoesNotAbortRemainingAppSettings() throws {
        let defaults = UserDefaults.standard
        let confirmQuitKey = AppCatalogSection().confirmQuitMode.userDefaultsKey
        let warnBeforeQuitKey = AppCatalogSection().warnBeforeQuit.userDefaultsKey

        try preservingDefaults(keys: [
            confirmQuitKey,
            warnBeforeQuitKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: confirmQuitKey)
            defaults.removeObject(forKey: warnBeforeQuitKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "confirmQuit": "sometimes",
                    "warnBeforeQuit": false
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.string(forKey: confirmQuitKey), ConfirmQuitMode.never.rawValue)
            XCTAssertEqual(defaults.object(forKey: warnBeforeQuitKey) as? Bool, false)
            XCTAssertEqual(QuitConfirmationStore(defaults: defaults).confirmQuitMode, .never)
        }
    }

    @MainActor
    func testInitialSettingsFileLoadImportsDefaultsWithoutLiveDefaultNotifications() throws {
        let defaults = UserDefaults.standard
        let scrollBarKey = TerminalScrollBarSettings.showScrollBarKey
        let autoResumeKey = AgentSessionAutoResumeSettings.autoResumeAgentSessionsKey

        try preservingDefaults(keys: [
            scrollBarKey,
            autoResumeKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: scrollBarKey)
            defaults.removeObject(forKey: autoResumeKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "terminal": {
                    "showScrollBar": false,
                    "autoResumeAgentSessions": false
                  }
                }
                """,
                to: settingsFileURL
            )

            let notificationCenter = NotificationCenter()
            var scrollBarNotificationCount = 0
            var autoResumeNotificationCount = 0
            let scrollBarObserver = notificationCenter.addObserver(
                forName: TerminalScrollBarSettings.didChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                scrollBarNotificationCount += 1
            }
            let autoResumeObserver = notificationCenter.addObserver(
                forName: AgentSessionAutoResumeSettings.didChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                autoResumeNotificationCount += 1
            }
            defer {
                notificationCenter.removeObserver(scrollBarObserver)
                notificationCenter.removeObserver(autoResumeObserver)
            }

            let store = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                notificationCenter: notificationCenter,
                startWatching: false
            )

            XCTAssertEqual(defaults.object(forKey: scrollBarKey) as? Bool, false)
            XCTAssertEqual(defaults.object(forKey: autoResumeKey) as? Bool, false)
            XCTAssertEqual(scrollBarNotificationCount, 0)
            XCTAssertEqual(autoResumeNotificationCount, 0)

            store.applyDeferredManagedDefaultSideEffects()

            XCTAssertEqual(scrollBarNotificationCount, 1)
            XCTAssertEqual(autoResumeNotificationCount, 1)
        }
    }

    func testSettingsFileStoreAppliesTerminalAgentAutoResumeSetting() throws {
        let defaults = UserDefaults.standard
        let key = AgentSessionAutoResumeSettings.autoResumeAgentSessionsKey
        let previousValue = defaults.object(forKey: key)
        let previousBackups = defaults.data(forKey: settingsFileBackupsDefaultsKey)
        let previousImportedDefaults = defaults.data(forKey: importedManagedDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }

            if let previousBackups {
                defaults.set(previousBackups, forKey: settingsFileBackupsDefaultsKey)
            } else {
                defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            }
            if let previousImportedDefaults {
                defaults.set(previousImportedDefaults, forKey: importedManagedDefaultsKey)
            } else {
                defaults.removeObject(forKey: importedManagedDefaultsKey)
            }
        }

        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
        defaults.removeObject(forKey: importedManagedDefaultsKey)

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "terminal": {
                "autoResumeAgentSessions": false
              }
            }
            """,
            to: settingsFileURL
        )

        _ = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
    }

    func testSettingsFileStoreAppliesTerminalTextBoxMaxLinesSetting() throws {
        let defaults = UserDefaults.standard
        try preservingDefaults(keys: [
            TerminalTextBoxInputSettings.maxLinesKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: TerminalTextBoxInputSettings.maxLinesKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "terminal": {
                    "textBoxMaxLines": 14
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.object(forKey: TerminalTextBoxInputSettings.maxLinesKey) as? Int, 14)
            XCTAssertEqual(TerminalTextBoxInputSettings.maxLines(defaults: defaults), 14)
        }
    }

    func testSettingsFileStoreAppliesFocusTextBoxOnNewTerminalsSetting() throws {
        let defaults = UserDefaults.standard
        let showKey = TerminalTextBoxInputSettings.showOnNewTerminalsKey
        let focusKey = TerminalTextBoxInputSettings.focusOnNewTerminalsKey
        try preservingDefaults(keys: [showKey, focusKey, settingsFileBackupsDefaultsKey, importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: showKey)
            defaults.removeObject(forKey: focusKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "terminal": {
                    "showTextBoxOnNewTerminals": true,
                    "focusTextBoxOnNewTerminals": true
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.object(forKey: showKey) as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: focusKey) as? Bool, true)
            XCTAssertTrue(TerminalTextBoxInputSettings.showOnNewTerminals(defaults: defaults))
            XCTAssertTrue(TerminalTextBoxInputSettings.focusOnNewTerminals(defaults: defaults))
        }
    }

    func testSettingsFileStoreAppliesTerminalCopyOnSelectSetting() throws {
        let defaults = UserDefaults.standard
        let key = TerminalCopyOnSelectSettings.copyOnSelectKey

        try preservingDefaults(keys: [key, settingsFileBackupsDefaultsKey, importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "terminal": {
                    "copyOnSelect": true
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
            XCTAssertEqual(
                TerminalCopyOnSelectSettings.ghosttyConfigContents(defaults: defaults),
                "copy-on-select = clipboard"
            )
        }
    }

    func testSettingsFileStoreAppliesAutomationRipgrepBinaryPath() throws {
        let defaults = UserDefaults.standard
        let key = "ripgrepCustomBinaryPath"

        try preservingDefaults(keys: [key, settingsFileBackupsDefaultsKey, importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "automation": {
                    "ripgrepBinaryPath": "/etc/profiles/per-user/nixuser/bin/rg"
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.string(forKey: key), "/etc/profiles/per-user/nixuser/bin/rg")
        }
    }

    func testSettingsFileStoreAppliesCustomBrowserSearchEngine() throws {
        let defaults = UserDefaults.standard
        try preservingDefaults(keys: [
            BrowserSearchSettingsStore.searchEngineKey,
            BrowserSearchSettingsStore.customSearchEngineNameKey,
            BrowserSearchSettingsStore.customSearchEngineURLTemplateKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: BrowserSearchSettingsStore.searchEngineKey)
            defaults.removeObject(forKey: BrowserSearchSettingsStore.customSearchEngineNameKey)
            defaults.removeObject(forKey: BrowserSearchSettingsStore.customSearchEngineURLTemplateKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "browser": {
                    "defaultSearchEngine": "custom",
                    "customSearchEngineName": "Kagi Site Search",
                    "customSearchEngineURLTemplate": "https://kagi.com/search?q={query}"
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            let configuration = BrowserSearchSettingsStore(defaults: defaults).currentConfiguration
            let url = try XCTUnwrap(configuration.searchURL(query: "browser settings"))

            XCTAssertEqual(configuration.engine, .custom)
            XCTAssertEqual(configuration.displayName, "Kagi Site Search")
            XCTAssertEqual(url.host, "kagi.com")
            XCTAssertTrue(url.absoluteString.contains("q=browser%20settings"))
        }
    }

    func testSettingsFileStoreAppliesBlankCustomBrowserSearchNameAndIgnoresInvalidCustomURLWithoutAbortingBrowserSection() throws {
        let defaults = UserDefaults.standard
        try preservingDefaults(keys: [
            BrowserSearchSettingsStore.searchEngineKey,
            BrowserSearchSettingsStore.customSearchEngineNameKey,
            BrowserSearchSettingsStore.customSearchEngineURLTemplateKey,
            BrowserSearchSettingsStore.searchSuggestionsEnabledKey,
            BrowserThemeSettings.modeKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: BrowserSearchSettingsStore.searchEngineKey)
            defaults.removeObject(forKey: BrowserSearchSettingsStore.customSearchEngineNameKey)
            defaults.removeObject(forKey: BrowserSearchSettingsStore.customSearchEngineURLTemplateKey)
            defaults.removeObject(forKey: BrowserSearchSettingsStore.searchSuggestionsEnabledKey)
            defaults.removeObject(forKey: BrowserThemeSettings.modeKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "browser": {
                    "defaultSearchEngine": "google",
                    "customSearchEngineName": "   ",
                    "customSearchEngineURLTemplate": "ftp://search.example.test?q={query}",
                    "showSearchSuggestions": false,
                    "theme": "dark"
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            XCTAssertEqual(defaults.string(forKey: BrowserSearchSettingsStore.searchEngineKey), BrowserSearchEngine.google.rawValue)
            XCTAssertEqual(
                defaults.string(forKey: BrowserSearchSettingsStore.customSearchEngineNameKey),
                BrowserSearchSettingsStore.defaultCustomSearchEngineName
            )
            XCTAssertNotEqual(
                defaults.string(forKey: BrowserSearchSettingsStore.customSearchEngineURLTemplateKey),
                "ftp://search.example.test?q={query}"
            )
            XCTAssertEqual(defaults.object(forKey: BrowserSearchSettingsStore.searchSuggestionsEnabledKey) as? Bool, false)
            XCTAssertEqual(defaults.string(forKey: BrowserThemeSettings.modeKey), BrowserThemeMode.dark.rawValue)
        }
    }

    func testSettingsFileStoreRejectsInvalidTerminalTextBoxMaxLinesSetting() throws {
        let defaults = UserDefaults.standard
        try preservingDefaults(keys: [
            TerminalTextBoxInputSettings.maxLinesKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            defaults.removeObject(forKey: TerminalTextBoxInputSettings.maxLinesKey)
            defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            defaults.removeObject(forKey: importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "terminal": {
                    "textBoxMaxLines": 100
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                startWatching: false
            )

            XCTAssertNil(defaults.object(forKey: TerminalTextBoxInputSettings.maxLinesKey))
            XCTAssertEqual(
                TerminalTextBoxInputSettings.maxLines(defaults: defaults),
                TerminalTextBoxInputSettings.defaultMaxLines
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mosaic-settings-startup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSettingsFile(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func preservingDefaults(keys: [String], _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previousValues = keys.map { key in
            (key: key, value: defaults.object(forKey: key))
        }
        defer {
            for previous in previousValues {
                if let value = previous.value {
                    defaults.set(value, forKey: previous.key)
                } else {
                    defaults.removeObject(forKey: previous.key)
                }
            }
        }
        try body()
    }
}
