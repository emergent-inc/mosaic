import Foundation
@testable import MosaicUpdater

/// A no-op ``UpdateLogging`` for tests that exercise the updater without asserting on log output.
struct NoopUpdateLog: UpdateLogging {
    func append(_ message: String) {}
    func logPath() -> String { "/dev/null" }
}
