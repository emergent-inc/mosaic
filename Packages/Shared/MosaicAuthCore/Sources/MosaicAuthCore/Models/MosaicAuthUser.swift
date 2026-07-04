import Foundation

/// The signed-in mosaic user, as both apps cache and display it.
///
/// A plain value mirrored from the auth user record. Codable so the
/// apps can persist it through ``MosaicAuthIdentityStore`` and restore the
/// identity card before the network session validates at launch.
public struct MosaicAuthUser: Codable, Equatable, Sendable {
    /// The auth provider user id.
    public let id: String
    /// The user's primary email, if one is set.
    public let primaryEmail: String?
    /// The user's display name, if one is set.
    public let displayName: String?
    /// The user's profile image URL, if one is set.
    public let imageURL: String?

    /// Creates a user value.
    /// - Parameters:
    ///   - id: The auth provider user id.
    ///   - primaryEmail: The user's primary email, if any.
    ///   - displayName: The user's display name, if any.
    ///   - imageURL: The user's profile image URL, if any.
    public init(id: String, primaryEmail: String?, displayName: String?, imageURL: String? = nil) {
        self.id = id
        self.primaryEmail = primaryEmail
        self.displayName = displayName
        self.imageURL = imageURL
    }
}
