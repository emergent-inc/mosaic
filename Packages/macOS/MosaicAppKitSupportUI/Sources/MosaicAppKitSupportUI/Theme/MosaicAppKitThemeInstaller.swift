public import AppKit

/// Installs a global AppKit theme by re-applying mosaic text and button colors
/// whenever a window becomes key or updates its view hierarchy.
@MainActor
public enum MosaicAppKitThemeInstaller {
    private static var isInstalled = false
    private static var observers: [NSObjectProtocol] = []

    public static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        applyThemeToAllWindows()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                applyTheme(to: window)
            },
            center.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                applyTheme(to: window)
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                applyThemeToAllWindows()
            },
        ]
    }

    private static func applyThemeToAllWindows() {
        for window in NSApp.windows {
            applyTheme(to: window)
        }
    }

    private static func applyTheme(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        MosaicAppKitTheme.applyRecursively(to: contentView)
    }
}
