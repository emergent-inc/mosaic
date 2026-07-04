import Foundation

/// Result returned after MOSAIC handles a provider mutation.
public struct MosaicSidebarProviderCommandResult: Codable, Equatable, Sendable {
    /// Whether MOSAIC accepted and completed the command.
    public var ok: Bool

    /// Creates a command result.
    public init(ok: Bool) {
        self.ok = ok
    }
}
