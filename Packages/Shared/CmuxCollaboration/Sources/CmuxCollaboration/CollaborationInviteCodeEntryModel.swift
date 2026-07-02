/// Normalizes user-entered collaboration invite codes for four-slot entry controls.
public struct CollaborationInviteCodeEntryModel: Equatable, Sendable {
    /// The number of visible code slots.
    public static let codeLength = 4

    /// The normalized uppercase entry value.
    public var value: String

    /// Creates an invite-code entry model.
    /// - Parameter value: The raw value typed or pasted by a user.
    public init(value: String = "") {
        self.value = Self.normalizedValue(from: value)
    }

    /// Returns `true` when all code slots are filled.
    public var isComplete: Bool {
        value.count == Self.codeLength
    }

    /// Returns a display character for each fixed code slot.
    public var displayCharacters: [String] {
        let characters = value.map(String.init)
        guard characters.count < Self.codeLength else { return Array(characters.prefix(Self.codeLength)) }
        return characters + Array(repeating: "", count: Self.codeLength - characters.count)
    }

    /// Replaces the current value with normalized user input.
    /// - Parameter newValue: The raw value typed or pasted by a user.
    public mutating func replace(with newValue: String) {
        value = Self.normalizedValue(from: newValue)
    }

    /// Returns uppercase invite-code letters, limited to the visible code length.
    /// - Parameter value: The raw value typed or pasted by a user.
    /// - Returns: A four-character-or-shorter code containing only supported letters.
    public static func normalizedValue(from value: String) -> String {
        value
            .uppercased()
            .unicodeScalars
            .filter(Self.isSupportedCodeLetter)
            .prefix(Self.codeLength)
            .map(String.init)
            .joined()
    }

    private static func isSupportedCodeLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) && scalar != "I" && scalar != "O"
    }
}
