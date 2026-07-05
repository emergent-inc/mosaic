import Foundation

/// Stable display numbers and accent colors for connected agent rooms.
///
/// Room numbers are assigned in first-seen wiring order so Room 1 is the first
/// linked group on this machine. Accent colors follow the same order (Room 1 →
/// first palette swatch) rather than a hash of the room id.
public enum AgentRoomDisplayPalette {
    /// Mosaic brand palette used to distinguish linked rooms at a glance.
    public static let accentHexColors: [String] = [
        "F0563F",
        "F6A623",
        "37C86B",
        "3E86F5",
        "8B5CF6",
        "2DA458",
        "336EC9",
        "724BCA",
        "C54734",
        "CA881D",
        "533794",
        "903426",
        "946415",
        "217840",
        "255093",
    ]

    /// Returns a 1-based room number for `roomID` using first-seen wiring order.
    public static func displayNumber(for roomID: String, orderedRoomIDs: [String]) -> Int {
        guard let index = orderedRoomIDs.firstIndex(of: roomID) else {
            return orderedRoomIDs.count + 1
        }
        return index + 1
    }

    /// Maps a 1-based room number to a palette index (Room 1 → first color).
    public static func paletteIndex(forDisplayNumber displayNumber: Int) -> Int {
        guard displayNumber > 0 else { return 0 }
        return (displayNumber - 1) % accentHexColors.count
    }

    /// Stable palette index from a room id. Prefer ``paletteIndex(forDisplayNumber:)``
    /// when a display number is available so colors track wiring order.
    public static func paletteIndex(for roomID: String) -> Int {
        let hash = stableHash(roomID)
        return Int(hash % UInt64(accentHexColors.count))
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ UInt64($1) }
    }
}
