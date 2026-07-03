/// Pure view model for the terminal recipient popover's primary action.
public struct CollaborationTerminalRecipientPopoverModel: Equatable, Sendable {
    /// The primary action the popover should offer.
    public enum PrimaryAction: Equatable, Sendable {
        /// Copy the session invite code so another person can join first.
        case copyInviteCode
        /// Apply the selected recipient set to an already-populated session.
        case shareWithSelectedRecipients
    }

    public let recipientCount: Int

    public init(recipientCount: Int) {
        self.recipientCount = max(0, recipientCount)
    }

    public var primaryAction: PrimaryAction {
        recipientCount == 0 ? .copyInviteCode : .shareWithSelectedRecipients
    }

    public var showsRecipientSelection: Bool {
        recipientCount > 0
    }

    public var showsInviteAction: Bool {
        primaryAction == .copyInviteCode
    }

    public var showsShareAction: Bool {
        primaryAction == .shareWithSelectedRecipients
    }

    /// Whether the popover should offer a way to stop hosting the terminal.
    public var showsStopSharingAction: Bool {
        true
    }
}
