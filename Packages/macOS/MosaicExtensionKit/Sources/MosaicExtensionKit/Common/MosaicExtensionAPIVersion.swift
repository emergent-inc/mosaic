import Foundation

public struct MosaicExtensionAPIVersion: Codable, Comparable, Equatable, Sendable {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let sidebarV2 = MosaicExtensionAPIVersion(major: 2, minor: 0)

    public static func < (lhs: MosaicExtensionAPIVersion, rhs: MosaicExtensionAPIVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }
}
