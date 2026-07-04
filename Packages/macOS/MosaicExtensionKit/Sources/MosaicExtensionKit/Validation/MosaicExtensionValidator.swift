import Foundation

/// Validates a sidebar extension manifest before MOSAIC trusts it.
@_spi(MosaicHostTransport)
public func validateSidebarManifest(
    _ manifest: MosaicExtensionManifest,
    supportedAPIVersion: MosaicExtensionAPIVersion = .sidebarV2
) throws {
    guard manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        throw MosaicExtensionValidationError.emptyIdentifier
    }
    guard manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        throw MosaicExtensionValidationError.emptyDisplayName
    }
    guard manifest.minimumAPIVersion.major == supportedAPIVersion.major,
          manifest.minimumAPIVersion <= supportedAPIVersion else {
        throw MosaicExtensionValidationError.unsupportedAPIVersion(
            requested: manifest.minimumAPIVersion,
            supported: supportedAPIVersion
        )
    }
}
