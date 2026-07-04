import AppKit
import MosaicWorkspaces
import Foundation

/// Opens workspace-group configuration and documentation surfaces.
enum SidebarWorkspaceGroupConfigOpener {
    /// Opens the mosaic config file (`~/.config/mosaic/mosaic.json`) in the user's
    /// configured editor, materializing an empty config first if none exists.
    @MainActor
    static func openMosaicConfigInEditor() {
        let opener = PreferredEditorService(defaults: .standard)
        openMosaicConfigInEditor(
            home: FileManager.default.homeDirectoryForCurrentUser,
            open: { opener.open($0) }
        )
    }

    /// Testable seam: resolves the mosaic config path under `home`, materializes
    /// an empty config if absent, then hands the file to `open`.
    ///
    /// The public ``openMosaicConfigInEditor()`` entry point passes
    /// `PreferredEditorService.open` so the config file honors
    /// `preferredEditorCommand` (with an OS-default fallback). Tests inject a
    /// capturing closure to assert the config file is routed through `open`.
    static func openMosaicConfigInEditor(home: URL, open: (URL) -> Void) {
        let configURL = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mosaic", isDirectory: true)
            .appendingPathComponent("mosaic.json", isDirectory: false)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try? Data("{}\n".utf8).write(to: configURL, options: .atomic)
        }
        open(configURL)
    }

    static func openWorkspaceGroupsDocs() {
        guard let url = URL(
            string: "https://github.com/emergent-inc/mosaic/blob/main/docs/workspace-groups.md"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
