public import Foundation

/// A request for the mosaic destination profile an import entry should write to.
public enum BrowserImportDestinationRequest: Equatable, Sendable {
    /// Import into the existing mosaic profile with this identifier.
    case existing(UUID)
    /// Create a new mosaic profile with this display name, then import into it.
    case createNamed(String)
}
