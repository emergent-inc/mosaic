import XCTest

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

final class KeyboardShortcutSettingsEqualizeSplitsTests: XCTestCase {
    func testSettingsFileStoreParsesEqualizeSplitsShortcut() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "shortcuts": {
                "equalizeSplits": "cmd+ctrl+e"
              }
            }
            """,
            to: settingsFileURL
        )

        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(
            store.override(for: .equalizeSplits),
            StoredShortcut(key: "e", command: true, shift: false, option: false, control: true)
        )
    }

    func testSettingsFileStoreParsesSystemWideHotkeyWithoutSharedStoreRecursion() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("mosaic.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "shortcuts": {
                "showHideAllWindows": "cmd+ctrl+."
              }
            }
            """,
            to: settingsFileURL
        )

        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(
            store.override(for: .showHideAllWindows),
            StoredShortcut(key: ".", command: true, shift: false, option: false, control: true)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func writeSettingsFile(_ contents: String, to url: URL) throws {
        try contents.data(using: .utf8)?.write(to: url)
    }
}
