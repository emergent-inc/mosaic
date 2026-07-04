import Foundation

@_spi(MosaicHostTransport)
public enum MosaicExtensionValidationError: Error, Equatable, Sendable {
    case unsupportedAPIVersion(requested: MosaicExtensionAPIVersion, supported: MosaicExtensionAPIVersion)
    case emptyIdentifier
    case emptyDisplayName
    case payloadTooLarge(kind: String, actualBytes: Int, maximumBytes: Int)
}
