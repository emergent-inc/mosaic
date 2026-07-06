public import Foundation

/// A directory invite the local user sent for a session they own: the signed
/// session descriptor plus every teammate user id it was sent to. Persisted so a
/// session that ends after an app relaunch can still withdraw its invites, which
/// otherwise linger in each teammate's inbox forever.
public struct CollaborationOutgoingInviteRecord: Codable, Equatable, Sendable {
    /// The normalized room key this record is stored under.
    public let roomKey: String
    /// The signed session descriptor replayed to withdraw the invite.
    public let descriptor: String
    /// The teammate user ids the session was shared with.
    public var inviteeUserIDs: [String]

    public init(roomKey: String, descriptor: String, inviteeUserIDs: [String]) {
        self.roomKey = roomKey
        self.descriptor = descriptor
        self.inviteeUserIDs = inviteeUserIDs
    }
}

/// Persists the directory invites the local user has sent, keyed by normalized
/// room key, so withdrawal survives an app relaunch. In-memory runtime state
/// remains the fast path; this store is the durable backstop.
public struct CollaborationOutgoingInviteStore {
    /// The default defaults key for persisted outgoing directory invites.
    public static let defaultKey = "collaboration.outgoingDirectoryInvites"

    private let defaults: UserDefaults
    private let storageKey: String

    /// Creates an outgoing-invite store.
    /// - Parameters:
    ///   - defaults: The defaults domain that persists the records.
    ///   - storageKey: The key used to persist the records.
    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.defaultKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    /// Returns all persisted records keyed by normalized room key.
    public func records() -> [String: CollaborationOutgoingInviteRecord] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        guard let stored = try? JSONDecoder().decode([CollaborationOutgoingInviteRecord].self, from: data) else {
            return [:]
        }
        return stored.reduce(into: [:]) { result, record in
            guard !record.roomKey.isEmpty, !record.descriptor.isEmpty else { return }
            result[record.roomKey] = record
        }
    }

    /// Returns the record for a room, if any.
    /// - Parameter roomKey: The normalized room key to look up.
    public func record(forRoomKey roomKey: String) -> CollaborationOutgoingInviteRecord? {
        records()[roomKey]
    }

    /// Records (or refreshes) the signed descriptor for a room, preserving any
    /// invitees already recorded for it.
    /// - Parameters:
    ///   - descriptor: The signed session descriptor.
    ///   - roomKey: The normalized room key.
    public func recordDescriptor(_ descriptor: String, forRoomKey roomKey: String) {
        guard !roomKey.isEmpty, !descriptor.isEmpty else { return }
        var all = records()
        let existing = all[roomKey]
        all[roomKey] = CollaborationOutgoingInviteRecord(
            roomKey: roomKey,
            descriptor: descriptor,
            inviteeUserIDs: existing?.inviteeUserIDs ?? []
        )
        persist(all)
    }

    /// Records that a room was shared with a teammate, storing the descriptor if
    /// it isn't already known.
    /// - Parameters:
    ///   - userID: The teammate user id the session was shared with.
    ///   - roomKey: The normalized room key.
    ///   - descriptor: The signed session descriptor.
    public func addInvitee(_ userID: String, forRoomKey roomKey: String, descriptor: String) {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomKey.isEmpty, !descriptor.isEmpty, !trimmed.isEmpty else { return }
        var all = records()
        var invitees = all[roomKey]?.inviteeUserIDs ?? []
        if !invitees.contains(trimmed) { invitees.append(trimmed) }
        all[roomKey] = CollaborationOutgoingInviteRecord(
            roomKey: roomKey,
            descriptor: descriptor,
            inviteeUserIDs: invitees
        )
        persist(all)
    }

    /// Removes and returns the record for a room.
    /// - Parameter roomKey: The normalized room key.
    @discardableResult
    public func remove(forRoomKey roomKey: String) -> CollaborationOutgoingInviteRecord? {
        var all = records()
        let removed = all.removeValue(forKey: roomKey)
        if removed != nil { persist(all) }
        return removed
    }

    /// Removes every persisted outgoing invite.
    public func removeAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private func persist(_ records: [String: CollaborationOutgoingInviteRecord]) {
        let sorted = records.values.sorted { $0.roomKey < $1.roomKey }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
