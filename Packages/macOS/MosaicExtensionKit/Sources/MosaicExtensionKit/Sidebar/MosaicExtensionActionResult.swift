import Foundation

@_spi(MosaicHostTransport)
/// Result returned by MOSAIC for a sidebar host action request.
public struct MosaicSidebarActionResult: Codable, Equatable, Sendable {
    /// Whether MOSAIC accepted and applied the action.
    public var accepted: Bool

    /// Optional host-supplied result or rejection message.
    public var message: String?

    /// Structured reason when the action was rejected.
    public var rejectionReason: MosaicSidebarActionRejectionReason?

    /// Creates an action result.
    public init(
        accepted: Bool,
        message: String? = nil,
        rejectionReason: MosaicSidebarActionRejectionReason? = nil
    ) {
        self.accepted = accepted
        self.message = message
        self.rejectionReason = accepted ? nil : rejectionReason
    }

    /// Successful action result.
    public static let accepted = MosaicSidebarActionResult(accepted: true)

    /// Creates a rejected action result with a displayable message.
    public static func rejected(
        _ message: String,
        reason: MosaicSidebarActionRejectionReason = .rejected
    ) -> MosaicSidebarActionResult {
        MosaicSidebarActionResult(accepted: false, message: message, rejectionReason: reason)
    }

    /// Rejected action result used when the caller cancels an in-flight request.
    public static let cancelled = MosaicSidebarActionResult(
        accepted: false,
        message: "Extension action was cancelled",
        rejectionReason: .cancelled
    )
}

@_spi(MosaicHostTransport)
/// Machine-readable reason MOSAIC rejected a sidebar action.
public enum MosaicSidebarActionRejectionReason: String, Codable, Equatable, Sendable {
    /// Generic host rejection.
    case rejected

    /// The caller cancelled the action before the host completed it.
    case cancelled
}

/// Error thrown by typed `MosaicSidebarHost` action helpers.
public enum MosaicSidebarActionError: Error, Equatable, Sendable {
    /// MOSAIC rejected the action with a displayable message.
    case rejected(String)

    /// The caller cancelled the action before completion.
    case cancelled
}
