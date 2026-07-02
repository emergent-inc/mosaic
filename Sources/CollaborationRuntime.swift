import AppKit
import CMUXMobileCore
import CmuxCollaboration
import Foundation
import Observation
import SwiftUI

@MainActor
protocol CollaborationEditablePanel: AnyObject {
    var collaborationFileURL: URL { get }
    var collaborationFilePath: String { get }
    var collaborationText: String { get }

    func applyCollaborationText(_ text: String)
}

struct CollaborationDocumentHeaderState: Equatable {
    var isShared = false
    var statusText = ""
    var peerSummary = ""
}

private struct CollaborationCreateSessionResponse: Decodable {
    let sessionID: String
    let sessionCode: String
}

private struct CollaborationPeerWire: Codable {
    let peerID: String
    let participantID: String?
    let displayName: String
    let color: String

    var stableParticipantID: String {
        participantID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? peerID
    }
}

private struct CollaborationJoinedWire: Decodable {
    let sessionID: String
    let peers: [CollaborationPeerWire]
}

private struct CollaborationFrameType: Decodable {
    let type: String
}

private struct CollaborationHeartbeatWire: Codable {
    let type = "peer.heartbeat"
}

private struct CollaborationDocumentUpdateWire: Codable {
    let type: String
    let documentID: String
    let updateID: String
    let operations: [TextOperation]
}

private struct CollaborationDocumentSnapshotWire: Codable {
    let type: String
    let documentID: String
    let requestID: String?
    let operations: [TextOperation]
    let textHash: String
}

private struct CollaborationDocumentSnapshotRequestWire: Codable {
    let type: String
    let documentID: String
    let requestID: String
}

private struct CollaborationTerminalOpenWire: Codable {
    let type: String
    let terminalID: String
    let descriptor: SharedTerminalDescriptor
    let fromPeerID: String?
    let recipientParticipantIDs: [String]?

    init(
        type: String,
        terminalID: String,
        descriptor: SharedTerminalDescriptor,
        fromPeerID: String? = nil,
        recipientParticipantIDs: [String]? = nil
    ) {
        self.type = type
        self.terminalID = terminalID
        self.descriptor = descriptor
        self.fromPeerID = fromPeerID
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

private struct CollaborationTerminalOutputWire: Codable {
    let type: String
    let terminalID: String
    let sequence: UInt64
    let dataBase64: String
    let fromPeerID: String?
    let caretPeerID: String?
    let recipientParticipantIDs: [String]?

    init(
        type: String,
        terminalID: String,
        sequence: UInt64,
        dataBase64: String,
        fromPeerID: String? = nil,
        caretPeerID: String? = nil,
        recipientParticipantIDs: [String]? = nil
    ) {
        self.type = type
        self.terminalID = terminalID
        self.sequence = sequence
        self.dataBase64 = dataBase64
        self.fromPeerID = fromPeerID
        self.caretPeerID = caretPeerID
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

private struct CollaborationTerminalRenderGridWire: Codable {
    let type: String
    let terminalID: String
    let frame: MobileTerminalRenderGridFrame
    let recipientParticipantIDs: [String]?

    init(
        type: String,
        terminalID: String,
        frame: MobileTerminalRenderGridFrame,
        recipientParticipantIDs: [String]? = nil
    ) {
        self.type = type
        self.terminalID = terminalID
        self.frame = frame
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

private struct CollaborationTerminalInputWire: Codable {
    let type: String
    let terminalID: String
    let inputID: String
    let dataBase64: String
    let fromPeerID: String?
    let recipientParticipantIDs: [String]?

    init(
        type: String,
        terminalID: String,
        inputID: String,
        dataBase64: String,
        fromPeerID: String? = nil,
        recipientParticipantIDs: [String]? = nil
    ) {
        self.type = type
        self.terminalID = terminalID
        self.inputID = inputID
        self.dataBase64 = dataBase64
        self.fromPeerID = fromPeerID
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

private struct CollaborationTerminalPointerWire: Codable {
    let type: String
    let terminalID: String
    let fromPeerID: String
    let recipientParticipantIDs: [String]?
    let x: Double
    let y: Double
    let visible: Bool
    let coordinateSpace: String?
    let row: Double?
    let column: Double?
    let contentRow: Double?
    let contentRowFromBottom: Double?
}

private struct CollaborationTerminalSelectionRectWire: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let row: Double?
    let column: Double?
    let rowFromBottom: Double?
    let widthColumns: Double?
    let heightRows: Double?
}

private struct CollaborationTerminalSelectionWire: Codable {
    let type: String
    let terminalID: String
    let fromPeerID: String
    let recipientParticipantIDs: [String]?
    let rects: [CollaborationTerminalSelectionRectWire]
    let visible: Bool
}

private struct CollaborationTerminalCloseWire: Codable {
    let type: String
    let terminalID: String
    let recipientParticipantIDs: [String]?

    init(type: String, terminalID: String, recipientParticipantIDs: [String]? = nil) {
        self.type = type
        self.terminalID = terminalID
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

private struct CollaborationAgentRoomEventWire: Codable {
    let type: String
    let event: ClaudeRoomEvent
}

private struct CollaborationAgentRoomSnapshotWire: Codable {
    let type: String
    let room: ClaudeRoomSnapshot
    let requestID: String?
}

private struct CollaborationAgentRoomSnapshotRequestWire: Codable {
    let type: String
    let roomID: String
    let requestID: String
}

private struct CollaborationAgentRoomCursorAckWire: Codable {
    let type: String
    let roomID: String
    let memberID: String
    let sequence: Int
}

private struct CollaborationPresenceWire: Codable {
    let type: String
    let peerID: String
    let displayName: String
    let color: String
    let activeFile: String?
    let cursor: Int
    let selectionLowerBound: Int?
    let selectionUpperBound: Int?
    let sequence: Int

    init(state: PresenceState) {
        self.type = "presence.update"
        self.peerID = state.peerID
        self.displayName = state.displayName
        self.color = state.color
        self.activeFile = state.activeFile
        self.cursor = state.cursor
        self.selectionLowerBound = state.selection?.lowerBound
        self.selectionUpperBound = state.selection?.upperBound
        self.sequence = state.sequence
    }

    var presenceState: PresenceState {
        let range: Range<Int>?
        if let selectionLowerBound, let selectionUpperBound {
            range = selectionLowerBound..<selectionUpperBound
        } else {
            range = nil
        }
        return PresenceState(
            peerID: peerID,
            displayName: displayName,
            color: color,
            activeFile: activeFile,
            cursor: cursor,
            selection: range,
            sequence: sequence
        )
    }
}

private struct CollaborationPeerLeftWire: Decodable {
    let peerID: String
}

private final class WeakCollaborationPanel {
    weak var panel: (any CollaborationEditablePanel)?

    init(_ panel: any CollaborationEditablePanel) {
        self.panel = panel
    }
}

private final class WeakCollaborationTerminalPanel {
    weak var panel: TerminalPanel?

    init(_ panel: TerminalPanel) {
        self.panel = panel
    }
}

private struct TerminalOutputCaretSuppression {
    let expiresAt: Date
}

@MainActor
private final class CollaborationRelayConnection {
    let sessionID: String
    let sessionCode: String
    let session: CollaborationSession
    var webSocketTask: URLSessionWebSocketTask?
    var eventsTask: Task<Void, Never>?
    var heartbeatTask: Task<Void, Never>?
    var peersByID: [String: CollaborationPeerWire] = [:]
    var connectionLabel = CollaborationStrings.connecting

    init(sessionID: String, sessionCode: String, session: CollaborationSession) {
        self.sessionID = sessionID
        self.sessionCode = sessionCode
        self.session = session
    }

    var peerSummary: String {
        if peersByID.isEmpty { return CollaborationStrings.noPeers }
        if peersByID.count == 1 { return CollaborationStrings.onePeer }
        return String(format: CollaborationStrings.peerCountFormat, peersByID.count)
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        eventsTask?.cancel()
        eventsTask = nil
    }
}

struct CollaborationTerminalHeaderState: Equatable {
    var isShared = false
    var statusText = ""
    var peerSummary = ""
}

struct CollaborationTerminalRecipientSnapshot: Equatable, Identifiable {
    let participantID: String
    let displayName: String
    let isSelected: Bool

    var id: String { participantID }
}

typealias CollaborationWorkspaceParticipantSnapshot = CollaborationParticipantAvatarSnapshot

struct AgentRoomHeaderState: Equatable {
    var isConnected = false
    var label = ""
}

private struct AgentRoomWireAnchor {
    let screenPoint: NSPoint
    weak var window: NSWindow?
}

@MainActor
private final class AgentRoomWireOverlayController {
    private var overlayWindow: NSWindow?
    private var overlayView: AgentRoomWireOverlayView?
    private var timer: Timer?

    func start(from sourceScreenPoint: NSPoint, in sourceWindow: NSWindow?) {
        stop()
        guard let sourceWindow else { return }

        let overlayView = AgentRoomWireOverlayView(frame: sourceWindow.frame)
        let overlayWindow = NSWindow(
            contentRect: sourceWindow.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1)
        overlayWindow.collectionBehavior = sourceWindow.collectionBehavior
        overlayWindow.contentView = overlayView
        sourceWindow.addChildWindow(overlayWindow, ordered: .above)

        self.overlayWindow = overlayWindow
        self.overlayView = overlayView
        overlayView.sourcePoint = overlayView.viewPoint(forScreenPoint: sourceScreenPoint, in: overlayWindow)
        updateEndPoint()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if (NSEvent.pressedMouseButtons & 1) == 0 {
                    self.stop()
                    return
                }
                self.updateEndPoint()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let overlayWindow, let parent = overlayWindow.parent {
            parent.removeChildWindow(overlayWindow)
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
    }

    private func updateEndPoint() {
        guard let overlayWindow, let overlayView else { return }
        overlayWindow.setFrame(overlayWindow.parent?.frame ?? overlayWindow.frame, display: false)
        overlayView.frame = NSRect(origin: .zero, size: overlayWindow.frame.size)
        overlayView.endPoint = overlayView.viewPoint(forScreenPoint: NSEvent.mouseLocation, in: overlayWindow)
        overlayView.needsDisplay = true
    }
}

private final class AgentRoomWireOverlayView: NSView {
    var sourcePoint: NSPoint = .zero
    var endPoint: NSPoint = .zero

    override var isFlipped: Bool { false }

    func viewPoint(forScreenPoint screenPoint: NSPoint, in window: NSWindow) -> NSPoint {
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard sourcePoint != endPoint else { return }

        let path = NSBezierPath()
        path.move(to: sourcePoint)
        let midX = (sourcePoint.x + endPoint.x) / 2
        path.curve(
            to: endPoint,
            controlPoint1: NSPoint(x: midX, y: sourcePoint.y),
            controlPoint2: NSPoint(x: midX, y: endPoint.y)
        )
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 12
        shadow.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.55)
        shadow.set()
        path.lineWidth = 9
        NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        path.lineWidth = 5
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        path.lineWidth = 2
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.stroke()

        drawEndpoint(at: sourcePoint, radius: 6)
        drawEndpoint(at: endPoint, radius: 6)
    }

    private func drawEndpoint(at point: NSPoint, radius: CGFloat) {
        let rect = NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let oval = NSBezierPath(ovalIn: rect)
        NSColor.controlAccentColor.setFill()
        oval.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        oval.lineWidth = 2
        oval.stroke()
    }
}

@MainActor
@Observable
final class CollaborationRuntime {
    static let shared = CollaborationRuntime()
    static let agentRoomWirePasteboardTypeIdentifier = "com.cmux.agent-room-wire"
    private static let defaultRelayURLString = "https://cmux-collaboration-worker.dorsa-rohani.workers.dev"
    private static let terminalInitialRenderGridScrollbackLines = 10_000
    private static let terminalLiveRenderGridScrollbackLines = 0
    private static let inviteCodeStore = CollaborationInviteCodeStore()
    private static let workspaceSessionStore = CollaborationWorkspaceSessionStore(
        inviteCodeStore: CollaborationRuntime.inviteCodeStore
    )
    private static let terminalRecipientSelectionStore = CollaborationTerminalRecipientSelectionStore(
        inviteCodeStore: CollaborationRuntime.inviteCodeStore
    )

    private(set) var relayURLString = CollaborationRuntime.defaultRelayURLString
    private(set) var sessionCode: String?
    private(set) var connectionLabel = CollaborationStrings.disconnected
    private(set) var lastErrorMessage: String?
    private(set) var workspaceParticipantSnapshotRevision = 0

    private let peerIdentity: CollaborationPeerIdentity
    private let localAvatarSeed: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var connectionsBySessionCode: [String: CollaborationRelayConnection] = [:]
    private var panelsByDocumentID: [String: WeakCollaborationPanel] = [:]
    private var descriptorsByDocumentID: [String: SharedFileDescriptor] = [:]
    private var sessionCodesByDocumentID: [String: String] = [:]
    private var statesByDocumentID: [String: CollaborationDocumentHeaderState] = [:]
    private var sessionCodesByWorkspaceID = CollaborationRuntime.workspaceSessionStore.bindingsByWorkspaceID()
        .mapValues(\.sessionCode)
    private var hostedTerminalsByID: [String: WeakCollaborationTerminalPanel] = [:]
    private var hostedTerminalIDsBySurfaceID: [UUID: String] = [:]
    private var terminalSessionRouter = CollaborationTerminalSessionRouter()
    private var hostedTerminalOutputSequencesByID: [String: UInt64] = [:]
    private var hostedTerminalOutputCaretSuppressionsByID: [String: TerminalOutputCaretSuppression] = [:]
    private var hostedTerminalRenderGridSnapshotTasksByID: [String: Task<Void, Never>] = [:]
    private var mirroredTerminalsByID: [String: WeakCollaborationTerminalPanel] = [:]
    private var mirroredTerminalIDsBySurfaceID: [UUID: String] = [:]
    private var terminalOwnerParticipantIDsByID: [String: String] = [:]
    private var mirroredTerminalRenderGridPatchSequencesByID: [String: UInt64] = [:]
    private var mirroredTerminalRenderGridSequencesByID: [String: UInt64] = [:]
    private var mirroredTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var hostedTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var terminalStatesByID: [String: CollaborationTerminalHeaderState] = [:]
    private var terminalPointerLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    private var terminalSelectionLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    private var snapshotFallbackTasks: [String: Task<Void, Never>] = [:]
    private var isPresentingStartDialog = false
    private let agentRoomStore = ClaudeRoomStore()
    private let agentRoomDigestBuilder = ClaudeRoomDigestBuilder()
    private var agentRoomIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomMemberIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomSnapshotsByID: [String: ClaudeRoomSnapshot] = [:]
    @ObservationIgnored private var agentRoomWireAnchorsBySurfaceID: [UUID: AgentRoomWireAnchor] = [:]
    @ObservationIgnored private let agentRoomWireOverlay = AgentRoomWireOverlayController()
    @ObservationIgnored private var draggingAgentRoomSourceSurfaceID: UUID?
    private var latestAgentRoomID: String?

    private init() {
        let displayName = NSFullUserName().isEmpty ? Host.current().localizedName ?? "cmux" : NSFullUserName()
        localAvatarSeed = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? displayName
        peerIdentity = CollaborationPeerIdentity.persistedParticipant(displayName: displayName)
    }

    private static func normalizedRelayURL(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRelayURLString : trimmed
    }

    private static func normalizedSessionCode(from value: String) -> String {
        inviteCodeStore.normalizedSessionCode(from: value)
    }

    private var activeConnection: CollaborationRelayConnection? {
        sessionCode.flatMap { connectionsBySessionCode[$0] }
    }

    private func sessionCode(forWorkspaceID workspaceID: UUID) -> String? {
        sessionCodesByWorkspaceID[workspaceID]
    }

    private func recordWorkspaceSession(_ sessionCode: String, workspaceID: UUID) {
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        sessionCodesByWorkspaceID[workspaceID] = normalizedCode
        Self.workspaceSessionStore.record(sessionCode: normalizedCode, forWorkspaceID: workspaceID)
        workspaceParticipantSnapshotRevision &+= 1
    }

    func participantSnapshots(forWorkspaceID workspaceID: UUID) -> [CollaborationWorkspaceParticipantSnapshot] {
        _ = workspaceParticipantSnapshotRevision
        guard let sessionCode = sessionCode(forWorkspaceID: workspaceID) else {
            return []
        }
        let local = CollaborationWorkspaceParticipantSnapshot.local(
            identity: peerIdentity,
            avatarSeed: localAvatarSeed
        )
        guard let connection = connectionsBySessionCode[sessionCode] else {
            return [local]
        }
        let peers = connection.peersByID.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { peer in
                CollaborationWorkspaceParticipantSnapshot.remote(
                    peerID: peer.peerID,
                    displayName: peer.displayName,
                    colorHex: peer.color
                )
            }
        return [local] + peers
    }

    private func connection(forTerminalID terminalID: String) -> CollaborationRelayConnection? {
        terminalSessionRouter.sessionCode(forTerminalID: terminalID).flatMap { connectionsBySessionCode[$0] }
    }

    private func terminalSelectionKey(for terminal: TerminalPanel) -> String {
        "\(terminal.workspaceId.uuidString):\(terminal.id.uuidString)"
    }

    private func participantID(for peerID: String?, in connection: CollaborationRelayConnection?) -> String? {
        guard let peerID else { return nil }
        if peerID == peerIdentity.peerID { return peerIdentity.participantID }
        return connection?.peersByID[peerID]?.stableParticipantID ?? peerID
    }

    private func currentRemoteParticipantIDs(in connection: CollaborationRelayConnection) -> Set<String> {
        Set(connection.peersByID.values.map(\.stableParticipantID))
    }

    private func selectedRecipientParticipantIDs(
        for terminalID: String,
        connection: CollaborationRelayConnection
    ) -> Set<String> {
        guard let panel = hostedTerminalsByID[terminalID]?.panel else { return [] }
        return Self.terminalRecipientSelectionStore.selectedParticipantIDs(
            sessionCode: connection.sessionCode,
            terminalKey: terminalSelectionKey(for: panel),
            currentParticipantIDs: Array(currentRemoteParticipantIDs(in: connection))
        )
    }

    private func recipientParticipantIDsForSending(
        terminalID: String,
        connection: CollaborationRelayConnection
    ) -> [String]? {
        guard hostedTerminalsByID[terminalID]?.panel != nil else {
            guard let ownerID = terminalOwnerParticipantIDsByID[terminalID] else { return nil }
            return [ownerID]
        }
        return Array(selectedRecipientParticipantIDs(for: terminalID, connection: connection)).sorted()
    }

    private func peerIsSelectedForHostedTerminal(
        terminalID: String,
        peerID: String?,
        connection: CollaborationRelayConnection
    ) -> Bool {
        guard hostedTerminalsByID[terminalID]?.panel != nil else { return true }
        guard let participantID = participantID(for: peerID, in: connection) else { return false }
        return selectedRecipientParticipantIDs(for: terminalID, connection: connection).contains(participantID)
    }

    func state(for panel: any CollaborationEditablePanel) -> CollaborationDocumentHeaderState {
        let descriptor = descriptor(for: panel)
        let documentID = descriptor.documentID(sessionID: sessionCode ?? "")
        let connection = activeConnection
        return statesByDocumentID[documentID] ?? CollaborationDocumentHeaderState(
            isShared: false,
            statusText: connection?.connectionLabel ?? connectionLabel,
            peerSummary: connection?.peerSummary ?? CollaborationStrings.noPeers
        )
    }

    func configureOrShare(panel: any CollaborationEditablePanel) {
        scheduleStartDialog(thenShare: panel)
    }

    func state(for terminal: TerminalPanel) -> CollaborationTerminalHeaderState {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id] ?? mirroredTerminalIDsBySurfaceID[terminal.id]
        if let terminalID, let state = terminalStatesByID[terminalID] {
            return state
        }
        let connection = activeConnection
        return CollaborationTerminalHeaderState(
            isShared: false,
            statusText: connection?.connectionLabel ?? connectionLabel,
            peerSummary: connection?.peerSummary ?? CollaborationStrings.noPeers
        )
    }

    func canManageRecipients(for terminal: TerminalPanel) -> Bool {
        hostedTerminalIDsBySurfaceID[terminal.id] != nil
    }

    func configureOrShare(terminal: TerminalPanel) {
        let workspaceSessionCode = sessionCode(forWorkspaceID: terminal.workspaceId)
        switch CollaborationTerminalShareAction.action(
            isShared: state(for: terminal).isShared,
            workspaceHasSession: workspaceSessionCode != nil
        ) {
        case .presentParticipantPicker:
            if !canManageRecipients(for: terminal) {
                leave(terminal: terminal)
            }
        case .rejoinWorkspaceSession:
            guard let workspaceSessionCode else {
                scheduleStartDialog(thenShare: terminal)
                return
            }
            Task {
                if let connection = await joinSession(code: workspaceSessionCode) {
                    share(terminal: terminal, via: connection)
                }
            }
        case .presentSessionChooser:
            scheduleStartDialog(thenShare: terminal)
        }
    }

    func recipientSnapshots(for terminal: TerminalPanel) -> [CollaborationTerminalRecipientSnapshot] {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id] ?? mirroredTerminalIDsBySurfaceID[terminal.id]
        guard let terminalID, let connection = connection(forTerminalID: terminalID) else { return [] }
        let selectedIDs = selectedRecipientParticipantIDs(for: terminalID, connection: connection)
        return connection.peersByID.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { peer in
                CollaborationTerminalRecipientSnapshot(
                    participantID: peer.stableParticipantID,
                    displayName: peer.displayName,
                    isSelected: selectedIDs.contains(peer.stableParticipantID)
                )
            }
    }

    func copyTerminalSessionInviteCode(for terminal: TerminalPanel) {
        let resolver = CollaborationTerminalInviteCodeResolver(
            hostedTerminalIDsBySurfaceID: hostedTerminalIDsBySurfaceID,
            terminalSessionRouter: terminalSessionRouter
        )
        guard let sessionCode = resolver.inviteCode(forHostedSurfaceID: terminal.id) else {
            return
        }
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(normalizedCode, forType: .string)
    }

    func applyRecipientSelection(_ selectedParticipantIDs: Set<String>, for terminal: TerminalPanel) {
        guard let terminalID = hostedTerminalIDsBySurfaceID[terminal.id], let connection = connection(forTerminalID: terminalID) else {
            return
        }
        let previousIDs = selectedRecipientParticipantIDs(for: terminalID, connection: connection)
        let knownIDs = currentRemoteParticipantIDs(in: connection)
        let nextIDs = selectedParticipantIDs.intersection(knownIDs)
        Self.terminalRecipientSelectionStore.record(
            selectedParticipantIDs: nextIDs,
            knownParticipantIDs: knownIDs,
            sessionCode: connection.sessionCode,
            terminalKey: terminalSelectionKey(for: terminal)
        )
        let removedIDs = previousIDs.subtracting(nextIDs)
        let addedIDs = nextIDs.subtracting(previousIDs)
        Task {
            if !removedIDs.isEmpty {
                try? await send(
                    CollaborationTerminalCloseWire(
                        type: "terminal.close",
                        terminalID: terminalID,
                        recipientParticipantIDs: Array(removedIDs).sorted()
                    ),
                    via: connection
                )
            }
            if !addedIDs.isEmpty {
                let descriptor = terminalDescriptor(for: terminal)
                let recipients = Array(addedIDs).sorted()
                try? await send(
                    CollaborationTerminalOpenWire(
                        type: "terminal.open",
                        terminalID: terminalID,
                        descriptor: descriptor,
                        recipientParticipantIDs: recipients
                    ),
                    via: connection
                )
                try? await sendTerminalRenderGridSnapshotIfPossible(
                    terminalID: terminalID,
                    scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                    full: true,
                    requireLiveScrollbackBottom: false,
                    recipientParticipantIDs: recipients,
                    via: connection
                )
            }
        }
    }

    func leave(terminal: TerminalPanel) {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id]
            ?? mirroredTerminalIDsBySurfaceID[terminal.id]
            ?? terminalID(for: terminal)
        let connection = connection(forTerminalID: terminalID)
        hostedTerminalsByID.removeValue(forKey: terminalID)
        removeTerminalSurfaceMappings(for: terminalID)
        hostedTerminalOutputSequencesByID.removeValue(forKey: terminalID)
        hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        hostedTerminalRenderGridSnapshotTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalsByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridPatchSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalInputReportPrefixesByID.removeValue(forKey: terminalID)
        hostedTerminalInputReportPrefixesByID.removeValue(forKey: terminalID)
        terminalStatesByID.removeValue(forKey: terminalID)
        terminalSessionRouter.remove(terminalID: terminalID)
        Task {
            if let connection {
                try? await send(.terminalClose(terminalID: terminalID), via: connection)
            }
        }
    }

    func noteTerminalOutput(surfaceID: UUID, data: Data) {
        guard let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] else { return }
        let sequence = hostedTerminalOutputSequencesByID[terminalID] ?? 0
        hostedTerminalOutputSequencesByID[terminalID] = sequence &+ UInt64(data.count)
        Task {
            if let connection = connection(forTerminalID: terminalID) {
                try? await send(.terminalOutput(terminalID: terminalID, sequence: sequence, data: data), via: connection)
                scheduleTerminalRenderGridSnapshot(terminalID: terminalID)
            }
        }
    }

    func noteTerminalInput(terminalID: String, data: Data) {
        guard let filteredData = Self.filteredTerminalCollaborationInput(
            data,
            pendingPrefix: &mirroredTerminalInputReportPrefixesByID[terminalID, default: Data()],
            direction: "mirror-to-host",
            terminalID: terminalID
        ) else { return }
        Task {
            if let connection = connection(forTerminalID: terminalID) {
                try? await send(.terminalInput(
                    terminalID: terminalID,
                    inputID: "\(peerIdentity.peerID)-\(UUID().uuidString)",
                    data: filteredData
                ), via: connection)
            }
        }
    }

    func noteTerminalPointer(
        surfaceID: UUID,
        normalizedX: Double,
        normalizedY: Double,
        row: Double?,
        column: Double?,
        contentRow: Double?,
        contentRowFromBottom: Double?,
        visible: Bool,
        coordinateSpace: String
    ) {
        let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] ?? mirroredTerminalIDsBySurfaceID[surfaceID]
        guard let terminalID else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if visible {
            let lastSentAt = terminalPointerLastSentAtBySurfaceID[surfaceID] ?? 0
            guard now - lastSentAt >= (1.0 / 60.0) else { return }
            terminalPointerLastSentAtBySurfaceID[surfaceID] = now
        } else {
            terminalPointerLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
        }

        Task {
            if let connection = connection(forTerminalID: terminalID) {
                try? await send(CollaborationTerminalPointerWire(
                    type: "terminal.pointer",
                    terminalID: terminalID,
                    fromPeerID: peerIdentity.peerID,
                    recipientParticipantIDs: recipientParticipantIDsForSending(
                        terminalID: terminalID,
                        connection: connection
                    ),
                    x: min(max(normalizedX, 0), 1),
                    y: min(max(normalizedY, 0), 1),
                    visible: visible,
                    coordinateSpace: coordinateSpace,
                    row: row,
                    column: column,
                    contentRow: contentRow,
                    contentRowFromBottom: contentRowFromBottom
                ), via: connection)
            }
        }
    }

    struct TerminalSelectionGridRect {
        let row: Double
        let column: Double
        let rowFromBottom: Double?
        let widthColumns: Double
        let heightRows: Double
    }

    func noteTerminalSelection(
        surfaceID: UUID,
        rects: [CGRect],
        gridRects: [TerminalSelectionGridRect],
        bounds: CGRect,
        visible: Bool
    ) {
        let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] ?? mirroredTerminalIDsBySurfaceID[surfaceID]
        guard let terminalID else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if visible {
            let lastSentAt = terminalSelectionLastSentAtBySurfaceID[surfaceID] ?? 0
            guard now - lastSentAt >= (1.0 / 12.0) else { return }
            terminalSelectionLastSentAtBySurfaceID[surfaceID] = now
        } else {
            terminalSelectionLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
        }

        let normalizedRects: [CollaborationTerminalSelectionRectWire]
        if visible, bounds.width > 0, bounds.height > 0 {
            normalizedRects = rects.enumerated().compactMap { index, rect in
                let clipped = rect.intersection(bounds)
                guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
                let gridRect = gridRects.indices.contains(index) ? gridRects[index] : nil
                return CollaborationTerminalSelectionRectWire(
                    x: Double(clipped.minX / bounds.width),
                    y: Double(clipped.minY / bounds.height),
                    width: Double(clipped.width / bounds.width),
                    height: Double(clipped.height / bounds.height),
                    row: gridRect?.row,
                    column: gridRect?.column,
                    rowFromBottom: gridRect?.rowFromBottom,
                    widthColumns: gridRect?.widthColumns,
                    heightRows: gridRect?.heightRows
                )
            }
        } else {
            normalizedRects = []
        }

        Task {
            if let connection = connection(forTerminalID: terminalID) {
                try? await send(CollaborationTerminalSelectionWire(
                    type: "terminal.selection",
                    terminalID: terminalID,
                    fromPeerID: peerIdentity.peerID,
                    recipientParticipantIDs: recipientParticipantIDsForSending(
                        terminalID: terminalID,
                        connection: connection
                    ),
                    rects: normalizedRects,
                    visible: visible && !normalizedRects.isEmpty
                ), via: connection)
            }
        }
    }

    private func peerVisibleToThisClient(
        _ peerID: String?,
        in connection: CollaborationRelayConnection?
    ) -> CollaborationPeerWire? {
        guard let peerID, peerID != peerIdentity.peerID else { return nil }
        return connection?.peersByID[peerID] ?? CollaborationPeerWire(
            peerID: peerID,
            participantID: nil,
            displayName: peerID,
            color: peerIdentity.color
        )
    }

    private func terminalOutputPeerID(for terminalID: String) -> String? {
        if let suppression = hostedTerminalOutputCaretSuppressionsByID[terminalID] {
            if suppression.expiresAt > Date() {
                return nil
            }
            hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        }
        return peerIdentity.peerID
    }

    private func removeTerminalSurfaceMappings(for terminalID: String) {
        let hostedSurfaceIDs = hostedTerminalIDsBySurfaceID
            .filter { $0.value == terminalID }
            .map(\.key)
        let mirroredSurfaceIDs = mirroredTerminalIDsBySurfaceID
            .filter { $0.value == terminalID }
            .map(\.key)

        hostedTerminalIDsBySurfaceID = hostedTerminalIDsBySurfaceID.filter { $0.value != terminalID }
        mirroredTerminalIDsBySurfaceID = mirroredTerminalIDsBySurfaceID.filter { $0.value != terminalID }
        terminalSessionRouter.remove(terminalID: terminalID)
        terminalOwnerParticipantIDsByID.removeValue(forKey: terminalID)
        for surfaceID in hostedSurfaceIDs + mirroredSurfaceIDs {
            terminalPointerLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
            terminalSelectionLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
        }
    }

    func leave(panel: any CollaborationEditablePanel) {
        guard let connection = activeConnection else { return }
        let descriptor = descriptor(for: panel)
        let documentID = descriptor.documentID(sessionID: connection.sessionCode)
        panelsByDocumentID.removeValue(forKey: documentID)
        descriptorsByDocumentID.removeValue(forKey: documentID)
        sessionCodesByDocumentID.removeValue(forKey: documentID)
        statesByDocumentID.removeValue(forKey: documentID)
        snapshotFallbackTasks[documentID]?.cancel()
        snapshotFallbackTasks.removeValue(forKey: documentID)
        Task {
            _ = try? await connection.session.close(file: descriptor)
        }
    }

    func noteLocalTextChange(panel: any CollaborationEditablePanel, previousText: String, nextText: String) {
        guard let connection = activeConnection else { return }
        let descriptor = descriptor(for: panel)
        let documentID = descriptor.documentID(sessionID: connection.sessionCode)
        guard panelsByDocumentID[documentID]?.panel != nil else { return }
        let edit = CollaborationTextDiff.diff(previous: previousText, next: nextText)
        Task {
            do {
                let frame = try await connection.session.applyLocalEdit(
                    file: descriptor,
                    range: edit.range,
                    replacement: edit.replacement
                )
                try await send(frame, via: connection)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func noteLocalSelection(panel: any CollaborationEditablePanel, textView: NSTextView) {
        guard let connection = activeConnection else { return }
        let selectedRange = textView.selectedRange()
        let selection: Range<Int>?
        if selectedRange.length > 0 {
            selection = selectedRange.location..<(selectedRange.location + selectedRange.length)
        } else {
            selection = nil
        }
        let descriptor = descriptor(for: panel)
        Task {
            let frame = await connection.session.setLocalSelection(
                file: descriptor,
                cursor: selectedRange.location,
                selection: selection
            )
            try? await send(frame, via: connection)
        }
    }

    func statusSummary() -> String {
        if let sessionCode {
            return "\(CollaborationStrings.connected): \(sessionCode)"
        }
        return connectionLabel
    }

    func agentRoomState(for panel: TerminalPanel) -> AgentRoomHeaderState {
        if let roomID = agentRoomIDsBySurfaceID[panel.id] {
            return AgentRoomHeaderState(
                isConnected: true,
                label: String(format: CollaborationStrings.agentRoomConnectedFormat, roomID.prefix(6).description)
            )
        }
        return AgentRoomHeaderState(isConnected: false, label: CollaborationStrings.connectClaudeRoom)
    }

    func beginAgentRoomWireDrag(sourcePanel: TerminalPanel) {
        draggingAgentRoomSourceSurfaceID = sourcePanel.id
        if let anchor = agentRoomWireAnchorsBySurfaceID[sourcePanel.id] {
            agentRoomWireOverlay.start(from: anchor.screenPoint, in: anchor.window)
        } else {
            agentRoomWireOverlay.start(from: NSEvent.mouseLocation, in: sourcePanel.surface.uiWindow)
        }
    }

    func endAgentRoomWireDrag() {
        draggingAgentRoomSourceSurfaceID = nil
        agentRoomWireOverlay.stop()
    }

    func updateAgentRoomWireAnchor(surfaceID: UUID, screenPoint: NSPoint, window: NSWindow?) {
        guard let window else {
            agentRoomWireAnchorsBySurfaceID.removeValue(forKey: surfaceID)
            return
        }
        agentRoomWireAnchorsBySurfaceID[surfaceID] = AgentRoomWireAnchor(screenPoint: screenPoint, window: window)
    }

    func removeAgentRoomWireAnchor(surfaceID: UUID) {
        agentRoomWireAnchorsBySurfaceID.removeValue(forKey: surfaceID)
    }

    func connectAgentRoomFromHeader(panel: TerminalPanel) {
        Task { @MainActor in
            if agentRoomIDsBySurfaceID[panel.id] != nil {
                _ = await disconnectAgentRoomSurfaceForAutomation(
                    roomID: nil,
                    surfaceID: panel.id.uuidString
                )
            } else {
                _ = await connectAgentRoomSurfaceForAutomation(
                    roomID: latestAgentRoomID,
                    surfaceID: panel.id.uuidString,
                    agentSessionID: nil,
                    displayName: panel.displayTitle
                )
            }
        }
    }

    func connectAgentRoomWire(sourceSurfaceID: String, targetPanel: TerminalPanel) {
        connectAgentRoomWire(sourceSurfaceID: sourceSurfaceID, targetSurfaceID: targetPanel.id)
    }

    func connectAgentRoomWire(sourceSurfaceID: String, targetSurfaceID: UUID) {
        Task { @MainActor in
            defer { endAgentRoomWireDrag() }
            let sourceUUID = UUID(uuidString: sourceSurfaceID)
            let targetUUID = targetSurfaceID
            let roomID = sourceUUID.flatMap { agentRoomIDsBySurfaceID[$0] }
                ?? agentRoomIDsBySurfaceID[targetUUID]
                ?? latestAgentRoomID
                ?? UUID().uuidString

            if let sourceUUID, sourceUUID != targetUUID {
                _ = await connectAgentRoomSurfaceForAutomation(
                    roomID: roomID,
                    surfaceID: sourceUUID.uuidString,
                    agentSessionID: nil,
                    displayName: terminalPanel(surfaceID: sourceUUID)?.displayTitle
                )
            }

            _ = await connectAgentRoomSurfaceForAutomation(
                roomID: roomID,
                surfaceID: targetUUID.uuidString,
                agentSessionID: nil,
                displayName: terminalPanel(surfaceID: targetUUID)?.displayTitle
            )
        }
    }

    func statusPayload() -> [String: Any] {
        let connection = activeConnection
        let peers = connection.map { Array($0.peersByID.values) } ?? []
        let payload: [String: Any] = [
            "connected": connection != nil,
            "relay_url": relayURLString,
            "session_code": sessionCode ?? NSNull(),
            "status": connection?.connectionLabel ?? connectionLabel,
            "session_count": connectionsBySessionCode.count,
            "shared_documents": statesByDocumentID.values.filter(\.isShared).count,
            "shared_terminals": terminalStatesByID.values.filter(\.isShared).count,
            "peers": peers.map { peer in
                [
                    "peer_id": peer.peerID,
                    "display_name": peer.displayName,
                    "color": peer.color,
                ]
            },
        ]
        return payload
    }

    func agentRoomStatusPayload() async -> [String: Any] {
        let rooms = await agentRoomStore.allRooms()
        cacheAgentRooms(rooms)
        return agentRoomStatusPayloadSnapshot()
    }

    func agentRoomStatusPayloadSnapshot() -> [String: Any] {
        [
            "rooms": agentRoomSnapshotsByID.values.sorted { $0.id < $1.id }.map(agentRoomPayload),
            "latest_room_id": latestAgentRoomID ?? NSNull(),
            "connected": activeConnection != nil,
            "relay_url": relayURLString,
            "session_code": sessionCode ?? NSNull(),
        ]
    }

    func createAgentRoomForAutomation(title: String?, deliveryPolicy: String?) async -> [String: Any] {
        let policy = ClaudeRoomDeliveryPolicy(rawValue: deliveryPolicy ?? "") ?? .manual
        let room = await agentRoomStore.createRoom(title: title, deliveryPolicy: policy)
        latestAgentRoomID = room.id
        cacheAgentRoom(room)
        return agentRoomPayload(room)
    }

    func createAgentRoomForAutomationRequest(title: String?, deliveryPolicy: String?) -> [String: Any] {
        Task { @MainActor in
            _ = await createAgentRoomForAutomation(title: title, deliveryPolicy: deliveryPolicy)
        }
        return ["requested": true]
    }

    func connectAgentRoomSurfaceForAutomation(
        roomID requestedRoomID: String?,
        surfaceID requestedSurfaceID: String?,
        agentSessionID: String?,
        displayName: String?
    ) async -> [String: Any] {
        let roomID = requestedRoomID ?? latestAgentRoomID ?? UUID().uuidString
        if latestAgentRoomID == nil {
            let room = await agentRoomStore.createRoom(id: roomID)
            cacheAgentRoom(room)
            latestAgentRoomID = roomID
        }
        guard let surfaceID = resolveAgentRoomSurfaceID(requestedSurfaceID) else {
            return ["connected": false, "error": "No terminal surface is available."]
        }
        let member = ClaudeRoomMember(
            surfaceID: surfaceID.uuidString,
            agentSessionID: agentSessionID,
            peerID: peerIdentity.peerID,
            displayName: displayName ?? terminalPanel(surfaceID: surfaceID)?.displayTitle
        )
        agentRoomIDsBySurfaceID[surfaceID] = roomID
        agentRoomMemberIDsBySurfaceID[surfaceID] = member.id
        let room = await agentRoomStore.connect(member: member, to: roomID)
        latestAgentRoomID = roomID
        cacheAgentRoom(room)
        try? await send(.agentRoomSnapshot(room))
        return agentRoomPayload(room)
    }

    func connectAgentRoomSurfaceForAutomationRequest(
        roomID: String?,
        surfaceID: String?,
        agentSessionID: String?,
        displayName: String?
    ) -> [String: Any] {
        Task { @MainActor in
            _ = await connectAgentRoomSurfaceForAutomation(
                roomID: roomID,
                surfaceID: surfaceID,
                agentSessionID: agentSessionID,
                displayName: displayName
            )
        }
        return ["requested": true]
    }

    func disconnectAgentRoomSurfaceForAutomation(roomID: String?, surfaceID: String?) async -> [String: Any] {
        let targetRoomID = roomID ?? latestAgentRoomID
        guard let targetRoomID else { return ["disconnected": false, "error": "No Claude room is active."] }
        let parsedSurfaceID = surfaceID.flatMap(UUID.init(uuidString:))
        let memberID = parsedSurfaceID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        let room = await agentRoomStore.disconnect(
            roomID: targetRoomID,
            memberID: memberID,
            surfaceID: surfaceID
        )
        if let parsedSurfaceID {
            agentRoomIDsBySurfaceID.removeValue(forKey: parsedSurfaceID)
            agentRoomMemberIDsBySurfaceID.removeValue(forKey: parsedSurfaceID)
        }
        if let room {
            cacheAgentRoom(room)
            try? await send(.agentRoomSnapshot(room))
            return agentRoomPayload(room)
        }
        return ["disconnected": false, "error": "Claude room not found."]
    }

    func disconnectAgentRoomSurfaceForAutomationRequest(roomID: String?, surfaceID: String?) -> [String: Any] {
        Task { @MainActor in
            _ = await disconnectAgentRoomSurfaceForAutomation(roomID: roomID, surfaceID: surfaceID)
        }
        return ["requested": true]
    }

    func postAgentRoomEventForAutomation(
        roomID requestedRoomID: String?,
        kind rawKind: String?,
        fromSurfaceID rawFromSurfaceID: String?,
        targetSurfaceIDs rawTargetSurfaceIDs: [String],
        text: String
    ) async -> [String: Any] {
        let fromSurfaceUUID = resolveAgentRoomSurfaceID(rawFromSurfaceID)
        let roomID: String?
        if let requestedRoomID {
            roomID = requestedRoomID
        } else if rawFromSurfaceID != nil {
            roomID = fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] }
        } else {
            roomID = fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] } ?? latestAgentRoomID
        }
        guard let roomID else { return ["posted": false, "error": "No Claude room is active."] }
        let kind = rawKind.flatMap(ClaudeRoomEventKind.init(rawValue:)) ?? .message
        let fromSurfaceID = fromSurfaceUUID?.uuidString ?? rawFromSurfaceID
        let fromMemberID = fromSurfaceUUID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        let result = await agentRoomStore.appendEvent(
            roomID: roomID,
            kind: kind,
            fromMemberID: fromMemberID,
            fromSurfaceID: fromSurfaceID,
            targetSurfaceIDs: rawTargetSurfaceIDs,
            text: text
        )
        cacheAgentRoom(result.room)
        try? await send(.agentRoomEvent(result.event))
        return [
            "posted": true,
            "event": encodedJSONObject(result.event),
            "room": agentRoomPayload(result.room),
        ]
    }

    func postAgentRoomEventForAutomationRequest(
        roomID: String?,
        kind: String?,
        fromSurfaceID: String?,
        targetSurfaceIDs: [String],
        text: String
    ) -> [String: Any] {
        let payload = postAgentRoomEventSnapshotForAutomation(
            roomID: roomID,
            kind: kind,
            fromSurfaceID: fromSurfaceID,
            targetSurfaceIDs: targetSurfaceIDs,
            text: text
        )
        if let room = payload["room_snapshot"] as? ClaudeRoomSnapshot,
           let event = payload["event_snapshot"] as? ClaudeRoomEvent {
            Task { @MainActor in
                await agentRoomStore.apply(snapshot: room)
                try? await send(.agentRoomEvent(event))
            }
            return [
                "posted": true,
                "event": encodedJSONObject(event),
                "room": agentRoomPayload(room),
            ]
        }
        if let publicPayload = payload["payload"] as? [String: Any] {
            return publicPayload
        }
        return ["posted": false, "error": "No Claude room is active."]
    }

    private func postAgentRoomEventSnapshotForAutomation(
        roomID requestedRoomID: String?,
        kind rawKind: String?,
        fromSurfaceID rawFromSurfaceID: String?,
        targetSurfaceIDs rawTargetSurfaceIDs: [String],
        text: String
    ) -> [String: Any] {
        let fromSurfaceUUID = resolveAgentRoomSurfaceID(rawFromSurfaceID)
        let roomID: String?
        if let requestedRoomID {
            roomID = requestedRoomID
        } else if rawFromSurfaceID != nil {
            roomID = fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] }
        } else {
            roomID = fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] } ?? latestAgentRoomID
        }
        guard let roomID else {
            return ["payload": ["posted": false, "error": "No Claude room is active."]]
        }
        let kind = rawKind.flatMap(ClaudeRoomEventKind.init(rawValue:)) ?? .message
        let fromSurfaceID = fromSurfaceUUID?.uuidString ?? rawFromSurfaceID
        let fromMemberID = fromSurfaceUUID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        var room = agentRoomSnapshotsByID[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        let event = ClaudeRoomEvent(
            sequence: room.lastSequence + 1,
            roomID: roomID,
            kind: kind,
            fromMemberID: fromMemberID,
            fromSurfaceID: fromSurfaceID,
            targetSurfaceIDs: rawTargetSurfaceIDs,
            text: text
        )
        room.lastSequence = event.sequence
        room.events.append(event)
        if room.events.count > 200 {
            room.events.removeFirst(room.events.count - 200)
        }
        cacheAgentRoom(room)
        latestAgentRoomID = roomID
        return [
            "room_snapshot": room,
            "event_snapshot": event,
        ]
    }

    func agentRoomDigestForAutomation(roomID requestedRoomID: String?, surfaceID rawSurfaceID: String? = nil, since: Int?) async -> [String: Any] {
        let surfaceUUID = resolveAgentRoomSurfaceID(rawSurfaceID)
        let roomID: String?
        if let requestedRoomID {
            roomID = requestedRoomID
        } else if rawSurfaceID != nil {
            roomID = surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] }
        } else {
            roomID = surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] } ?? latestAgentRoomID
        }
        guard let roomID, let room = await agentRoomStore.room(id: roomID) else {
            return ["digest": "", "error": "Claude room not found."]
        }
        cacheAgentRoom(room)
        return agentRoomDigestPayload(room: room, surfaceID: surfaceUUID?.uuidString, since: since)
    }

    func agentRoomDigestPayloadSnapshot(roomID requestedRoomID: String?, surfaceID rawSurfaceID: String? = nil, since: Int?) -> [String: Any] {
        let surfaceUUID = resolveAgentRoomSurfaceID(rawSurfaceID)
        let roomID: String?
        if let requestedRoomID {
            roomID = requestedRoomID
        } else if rawSurfaceID != nil {
            roomID = surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] }
        } else {
            roomID = surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] } ?? latestAgentRoomID
        }
        guard let roomID, let room = agentRoomSnapshotsByID[roomID] else {
            return ["digest": "", "error": "Claude room not found."]
        }
        return agentRoomDigestPayload(room: room, surfaceID: surfaceUUID?.uuidString, since: since)
    }

    private func agentRoomDigestPayload(room: ClaudeRoomSnapshot, surfaceID: String?, since: Int?) -> [String: Any] {
        let digestRoom: ClaudeRoomSnapshot
        if let surfaceID {
            var filtered = room
            filtered.events = room.events.filter { event in
                event.fromSurfaceID != surfaceID &&
                    (event.targetSurfaceIDs.isEmpty || event.targetSurfaceIDs.contains(surfaceID))
            }
            digestRoom = filtered
        } else {
            digestRoom = room
        }
        return [
            "room_id": room.id,
            "digest": agentRoomDigestBuilder.digest(for: digestRoom, since: since),
            "last_sequence": room.lastSequence,
        ]
    }

    func agentRoomDigestForAutomationRequest(roomID: String?, surfaceID: String? = nil, since: Int?) -> [String: Any] {
        Task { @MainActor in
            _ = await agentRoomDigestForAutomation(roomID: roomID, surfaceID: surfaceID, since: since)
        }
        return ["requested": true]
    }

    func createSessionForAutomation(relayURL: String?) async -> [String: Any] {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        do {
            let response = try await createSession()
            await connect(sessionID: response.sessionID, code: response.sessionCode)
            var payload = statusPayload()
            payload["session_code"] = response.sessionCode
            return payload
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
            return [
                "connected": false,
                "status": connectionLabel,
                "error": error.localizedDescription,
            ]
        }
    }

    func createSessionForAutomationRequest(relayURL: String?) -> [String: Any] {
        Task { @MainActor in
            _ = await createSessionForAutomation(relayURL: relayURL)
        }
        return [
            "requested": true,
            "status": CollaborationStrings.connecting,
        ]
    }

    func joinSessionForAutomation(relayURL: String?, code: String) async -> [String: Any] {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        await joinSession(code: code)
        return statusPayload()
    }

    func joinSessionForAutomationRequest(relayURL: String?, code: String) -> [String: Any] {
        Task { @MainActor in
            _ = await joinSessionForAutomation(relayURL: relayURL, code: code)
        }
        return [
            "requested": true,
            "session_code": Self.normalizedSessionCode(from: code),
            "status": CollaborationStrings.connecting,
        ]
    }

    func shareSelectedTerminalForAutomation() -> [String: Any] {
        guard let workspace = TerminalController.shared.tabManager?.selectedWorkspace
            ?? TerminalController.shared.tabManager?.tabs.first else {
            return [
                "shared": false,
                "error": CollaborationStrings.noWorkspaceForTerminalShare,
            ]
        }
        guard let terminal = workspace.focusedTerminalPanel
            ?? workspace.panels.values.compactMap({ $0 as? TerminalPanel }).first else {
            return [
                "shared": false,
                "error": CollaborationStrings.terminalShareFailed,
            ]
        }
        configureOrShare(terminal: terminal)
        return statusPayload()
    }

    func leaveSessionForAutomation() -> [String: Any] {
        disconnectAllConnections()
        sessionCode = nil
        panelsByDocumentID.removeAll()
        descriptorsByDocumentID.removeAll()
        sessionCodesByDocumentID.removeAll()
        statesByDocumentID.removeAll()
        sessionCodesByWorkspaceID.removeAll()
        Self.workspaceSessionStore.removeAll()
        hostedTerminalsByID.removeAll()
        hostedTerminalIDsBySurfaceID.removeAll()
        terminalSessionRouter.removeAll()
        hostedTerminalOutputSequencesByID.removeAll()
        hostedTerminalOutputCaretSuppressionsByID.removeAll()
        hostedTerminalRenderGridSnapshotTasksByID.values.forEach { $0.cancel() }
        hostedTerminalRenderGridSnapshotTasksByID.removeAll()
        mirroredTerminalsByID.removeAll()
        mirroredTerminalIDsBySurfaceID.removeAll()
        mirroredTerminalRenderGridPatchSequencesByID.removeAll()
        mirroredTerminalRenderGridSequencesByID.removeAll()
        mirroredTerminalInputReportPrefixesByID.removeAll()
        hostedTerminalInputReportPrefixesByID.removeAll()
        terminalOwnerParticipantIDsByID.removeAll()
        terminalStatesByID.removeAll()
        terminalPointerLastSentAtBySurfaceID.removeAll()
        terminalSelectionLastSentAtBySurfaceID.removeAll()
        connectionLabel = CollaborationStrings.disconnected
        workspaceParticipantSnapshotRevision &+= 1
        return statusPayload()
    }

    private func scheduleStartDialog() {
        guard !isPresentingStartDialog else { return }
        isPresentingStartDialog = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentStartDialog()
            self.isPresentingStartDialog = false
        }
    }

    private func scheduleStartDialog(thenShare terminal: TerminalPanel) {
        guard !isPresentingStartDialog else { return }
        isPresentingStartDialog = true
        DispatchQueue.main.async { [weak self, terminal] in
            guard let self else { return }
            self.presentStartDialog(thenShare: terminal)
            self.isPresentingStartDialog = false
        }
    }

    private func scheduleStartDialog(thenShare panel: any CollaborationEditablePanel) {
        guard !isPresentingStartDialog else { return }
        isPresentingStartDialog = true
        DispatchQueue.main.async { [weak self, panel] in
            guard let self else { return }
            self.presentStartDialog(thenShare: panel)
            self.isPresentingStartDialog = false
        }
    }

    private func presentStartDialog() {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.startTitle
        alert.informativeText = CollaborationStrings.startMessage
        alert.addButton(withTitle: CollaborationStrings.createSession)
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { await createSessionAndPresentCode(relayURL: nil) }
        case .alertSecondButtonReturn:
            presentJoinDialog()
        default:
            break
        }
    }

    private func presentJoinDialog() {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.joinSession
        alert.informativeText = CollaborationStrings.joinMessage
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        let codeField = NSTextField(string: "")
        codeField.placeholderString = CollaborationStrings.sessionCodePlaceholder
        stack.addArrangedSubview(codeField)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let code = Self.normalizedSessionCode(from: codeField.stringValue)
        Task { await joinSession(code: code) }
    }

    private func presentStartDialog(thenShare panel: any CollaborationEditablePanel) {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.startTitle
        alert.informativeText = CollaborationStrings.startMessage
        alert.addButton(withTitle: CollaborationStrings.createSession)
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { await createSessionAndShare(panel: panel) }
        case .alertSecondButtonReturn:
            presentJoinDialog(thenShare: panel)
        default:
            break
        }
    }

    private func presentStartDialog(thenShare terminal: TerminalPanel) {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.startTitle
        alert.informativeText = CollaborationStrings.startMessage
        alert.addButton(withTitle: CollaborationStrings.createSession)
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let response = alert.runModal()
        switch CollaborationTerminalStartDialogAction.action(
            buttonIndex: Self.alertButtonIndex(for: response)
        ) {
        case .createSessionAndShareTerminal:
            Task { await createSessionAndShare(terminal: terminal) }
        case .joinSessionAndBindWorkspace:
            presentJoinDialog(thenBindWorkspaceFor: terminal)
        case .cancel:
            break
        }
    }

    private static func alertButtonIndex(for response: NSApplication.ModalResponse) -> Int {
        switch response {
        case .alertFirstButtonReturn:
            return 1
        case .alertSecondButtonReturn:
            return 2
        case .alertThirdButtonReturn:
            return 3
        default:
            return 0
        }
    }

    private func presentJoinDialog(thenShare panel: any CollaborationEditablePanel) {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.joinSession
        alert.informativeText = CollaborationStrings.joinMessage
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        let codeField = NSTextField(string: "")
        codeField.placeholderString = CollaborationStrings.sessionCodePlaceholder
        stack.addArrangedSubview(codeField)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let code = Self.normalizedSessionCode(from: codeField.stringValue)
        Task {
            await joinSession(code: code)
            share(panel: panel)
        }
    }

    private func presentJoinDialog(thenBindWorkspaceFor terminal: TerminalPanel) {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.joinSession
        alert.informativeText = CollaborationStrings.joinMessage
        alert.addButton(withTitle: CollaborationStrings.joinSession)
        alert.addButton(withTitle: CollaborationStrings.cancel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        let codeField = NSTextField(string: "")
        codeField.placeholderString = CollaborationStrings.sessionCodePlaceholder
        stack.addArrangedSubview(codeField)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let code = Self.normalizedSessionCode(from: codeField.stringValue)
        Task {
            if let connection = await joinSession(code: code) {
                recordWorkspaceSession(connection.sessionCode, workspaceID: terminal.workspaceId)
            }
        }
    }

    private func configureCollaborationAlertChrome(_ alert: NSAlert) {
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
    }

    private func createSessionAndPresentCode(relayURL: String?) async {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        do {
            let response = try await createSession()
            await connect(sessionID: response.sessionID, code: response.sessionCode)
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
        }
    }

    private func createSessionAndShare(panel: any CollaborationEditablePanel) async {
        do {
            let response = try await createSession()
            await connect(sessionID: response.sessionID, code: response.sessionCode)
            share(panel: panel)
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
        }
    }

    private func createSessionAndShare(terminal: TerminalPanel) async {
        do {
            let response = try await createSession()
            if let connection = await connect(sessionID: response.sessionID, code: response.sessionCode) {
                share(terminal: terminal, via: connection)
            }
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
        }
    }

    private func presentCreatedSessionDialog(code: String) {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.sessionCreatedTitle
        alert.informativeText = CollaborationStrings.sessionCreatedMessage(code: normalizedCode)
        alert.addButton(withTitle: CollaborationStrings.copyCode)
        alert.addButton(withTitle: CollaborationStrings.done)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 48)

        let codeField = NSTextField(string: normalizedCode)
        codeField.isEditable = false
        codeField.isSelectable = true
        codeField.alignment = .center
        codeField.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(codeField)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(normalizedCode, forType: .string)
    }

    @discardableResult
    private func joinSession(code: String) async -> CollaborationRelayConnection? {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        return await connect(sessionID: normalizedCode, code: normalizedCode)
    }

    private func createSession() async throws -> CollaborationCreateSessionResponse {
        guard let url = URL(string: relayURLString)?
            .appending(path: "v1")
            .appending(path: "collaboration")
            .appending(path: "sessions") else {
            throw CollaborationRuntimeError.invalidRelayURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CollaborationRuntimeError.relayRejected
        }
        return try decoder.decode(CollaborationCreateSessionResponse.self, from: data)
    }

    private func connect(sessionID: String, code: String) async -> CollaborationRelayConnection? {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        if let existing = connectionsBySessionCode[normalizedCode] {
            sessionCode = normalizedCode
            connectionLabel = existing.connectionLabel
            reopenSharedDocumentsForCurrentSession()
            return existing
        }

        sessionCode = normalizedCode
        connectionLabel = CollaborationStrings.connecting
        let nextSession = CollaborationSession(
            peerID: peerIdentity.peerID,
            displayName: peerIdentity.displayName,
            color: peerIdentity.color,
            sessionID: sessionID
        )
        let connection = CollaborationRelayConnection(
            sessionID: sessionID,
            sessionCode: normalizedCode,
            session: nextSession
        )
        connectionsBySessionCode[normalizedCode] = connection
        observe(connection: connection)

        guard let url = connectURL(code: normalizedCode) else {
            connectionLabel = CollaborationStrings.connectionFailed
            connection.connectionLabel = CollaborationStrings.connectionFailed
            await nextSession.markRelayUnavailable()
            return nil
        }
        let task = URLSession.shared.webSocketTask(with: url)
        connection.webSocketTask = task
        task.resume()
        receiveNextMessage(for: connection)
        startHeartbeatLoop(for: connection)
        await nextSession.markConnected()
        connection.connectionLabel = CollaborationStrings.connected
        connectionLabel = CollaborationStrings.connected
        reopenSharedDocumentsForCurrentSession()
        return connection
    }

    private func connectURL(code: String) -> URL? {
        guard var components = URLComponents(string: relayURLString) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/v1/collaboration/sessions/\(Self.normalizedSessionCode(from: code))/connect"
        components.queryItems = [
            URLQueryItem(name: "peerID", value: peerIdentity.peerID),
            URLQueryItem(name: "participantID", value: peerIdentity.participantID),
            URLQueryItem(name: "displayName", value: peerIdentity.displayName),
            URLQueryItem(name: "color", value: peerIdentity.color),
        ]
        return components.url
    }

    private func observe(connection: CollaborationRelayConnection) {
        connection.eventsTask?.cancel()
        let sessionCode = connection.sessionCode
        connection.eventsTask = Task { [weak self, weak connection] in
            guard let connection else { return }
            let events = await connection.session.events
            for await event in events {
                await self?.handle(event: event, sessionCode: sessionCode)
            }
        }
    }

    private func share(panel: any CollaborationEditablePanel) {
        guard let connection = activeConnection else { return }
        let descriptor = descriptor(for: panel)
        let documentID = descriptor.documentID(sessionID: connection.sessionCode)
        panelsByDocumentID[documentID] = WeakCollaborationPanel(panel)
        descriptorsByDocumentID[documentID] = descriptor
        sessionCodesByDocumentID[documentID] = connection.sessionCode
        statesByDocumentID[documentID] = CollaborationDocumentHeaderState(
            isShared: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary
        )
        Task {
            do {
                _ = try await connection.session.open(file: descriptor)
                if connection.peersByID.isEmpty {
                    try await send(try await connection.session.snapshotFrame(for: descriptor), via: connection)
                } else {
                    let requestID = UUID().uuidString
                    try await sendSnapshotRequest(documentID: documentID, requestID: requestID, via: connection)
                    scheduleSnapshotFallback(descriptor: descriptor, documentID: documentID)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func share(terminal: TerminalPanel) {
        guard let connection = activeConnection else { return }
        share(terminal: terminal, via: connection)
    }

    private func share(terminal: TerminalPanel, via connection: CollaborationRelayConnection) {
        let descriptor = terminalDescriptor(for: terminal)
        let terminalID = descriptor.terminalID(sessionID: connection.sessionCode)
        recordWorkspaceSession(connection.sessionCode, workspaceID: terminal.workspaceId)
        hostedTerminalsByID[terminalID] = WeakCollaborationTerminalPanel(terminal)
        hostedTerminalIDsBySurfaceID[terminal.id] = terminalID
        terminalOwnerParticipantIDsByID[terminalID] = peerIdentity.participantID
        terminalSessionRouter.record(terminalID: terminalID, sessionCode: connection.sessionCode)
        terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
            isShared: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary
        )
        Task {
            do {
                try await send(.terminalOpen(terminalID: terminalID, descriptor: descriptor), via: connection)
                try await sendTerminalRenderGridSnapshotIfPossible(
                    terminalID: terminalID,
                    scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                    full: true,
                    requireLiveScrollbackBottom: false,
                    via: connection
                )
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func reopenSharedDocumentsForCurrentSession() {
        guard let connection = activeConnection else { return }
        let openPanels = panelsByDocumentID.values.compactMap(\.panel)
        guard !openPanels.isEmpty else { return }

        snapshotFallbackTasks.values.forEach { $0.cancel() }
        snapshotFallbackTasks.removeAll()

        panelsByDocumentID.removeAll()
        descriptorsByDocumentID.removeAll()
        sessionCodesByDocumentID.removeAll()
        statesByDocumentID.removeAll()

        for panel in openPanels {
            let descriptor = descriptor(for: panel)
            let documentID = descriptor.documentID(sessionID: connection.sessionCode)
            panelsByDocumentID[documentID] = WeakCollaborationPanel(panel)
            descriptorsByDocumentID[documentID] = descriptor
            sessionCodesByDocumentID[documentID] = connection.sessionCode
            statesByDocumentID[documentID] = CollaborationDocumentHeaderState(
                isShared: true,
                statusText: CollaborationStrings.shared,
                peerSummary: connection.peerSummary
            )
            Task {
                do {
                    _ = try await connection.session.open(file: descriptor)
                    try await send(try await connection.session.snapshotFrame(for: descriptor), via: connection)
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func scheduleSnapshotFallback(descriptor: SharedFileDescriptor, documentID: String) {
        snapshotFallbackTasks[documentID]?.cancel()
        snapshotFallbackTasks[documentID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sendLocalSnapshotIfOpen(descriptor: descriptor)
        }
    }

    private func sendLocalSnapshotIfOpen(descriptor: SharedFileDescriptor) async {
        guard let connection = activeConnection else { return }
        do {
            try await send(try await connection.session.snapshotFrame(for: descriptor), via: connection)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleRemoteTerminalOpen(
        terminalID: String,
        descriptor: SharedTerminalDescriptor,
        ownerPeerID: String?,
        connection: CollaborationRelayConnection
    ) {
        if mirroredTerminalsByID[terminalID]?.panel != nil { return }
        let title = descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? CollaborationStrings.sharedTerminalTitle : title
        guard let workspace = TerminalController.shared.tabManager?.selectedWorkspace
            ?? TerminalController.shared.tabManager?.tabs.first else {
            lastErrorMessage = CollaborationStrings.noWorkspaceForTerminalShare
            return
        }
        guard let panel = workspace.addRemoteTmuxDisplayPane(
            remotePaneId: terminalID.hashValue,
            title: displayTitle,
            focus: false,
            onInput: { [terminalID] data in
                Task { @MainActor in
                    CollaborationRuntime.shared.noteTerminalInput(terminalID: terminalID, data: data)
                }
            }
        ) else {
            lastErrorMessage = CollaborationStrings.terminalShareFailed
            return
        }
        panel.surface.suppressPassiveMouseInput = true
        mirroredTerminalsByID[terminalID] = WeakCollaborationTerminalPanel(panel)
        mirroredTerminalIDsBySurfaceID[panel.id] = terminalID
        terminalOwnerParticipantIDsByID[terminalID] = participantID(for: ownerPeerID, in: connection)
        mirroredTerminalRenderGridPatchSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridSequencesByID.removeValue(forKey: terminalID)
        terminalSessionRouter.record(terminalID: terminalID, sessionCode: connection.sessionCode)
        terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
            isShared: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary
        )
    }

    private func handleRemoteTerminalOutput(
        terminalID: String,
        sequence: UInt64,
        data: Data,
        caretPeerID: String?,
        connection: CollaborationRelayConnection
    ) {
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        let endSequence = sequence &+ UInt64(data.count)
        if let renderGridSequence = mirroredTerminalRenderGridSequencesByID[terminalID] {
            guard endSequence > renderGridSequence else { return }
            if sequence < renderGridSequence {
                let trimCount = Int(renderGridSequence - sequence)
                guard trimCount < data.count else { return }
                panel.surface.processRemoteOutput(Data(data.dropFirst(trimCount)))
            } else {
                panel.surface.processRemoteOutput(data)
            }
        } else {
            panel.surface.processRemoteOutput(data)
        }
        if let peer = peerVisibleToThisClient(caretPeerID, in: connection) {
            panel.surface.hostedView.showTerminalCollaboratorCaret(
                peerID: peer.peerID,
                displayName: peer.displayName,
                colorHex: peer.color
            )
        }
    }

    private func handleRemoteTerminalRenderGrid(terminalID: String, frame: MobileTerminalRenderGridFrame) {
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        if let patchSequence = mirroredTerminalRenderGridPatchSequencesByID[terminalID],
           frame.stateSeq < patchSequence {
            return
        }
        var mirrorFrame = frame
        mirrorFrame.modes.removeAll(where: Self.isMirrorInputReportingMode)
        panel.surface.processRemoteOutput(mirrorFrame.vtPatchBytes())
        mirroredTerminalRenderGridPatchSequencesByID[terminalID] = max(
            mirroredTerminalRenderGridPatchSequencesByID[terminalID] ?? 0,
            frame.stateSeq
        )
        if frame.full {
            mirroredTerminalRenderGridSequencesByID[terminalID] = max(
                mirroredTerminalRenderGridSequencesByID[terminalID] ?? 0,
                frame.stateSeq
            )
        }
    }

    private static func isMirrorInputReportingMode(_ mode: MobileTerminalRenderGridFrame.ModeSetting) -> Bool {
        guard !mode.ansi else { return false }
        switch mode.code {
        case 9, 1000, 1002, 1003, 1004, 1005, 1006, 1007, 1015, 1016, 2004, 2027:
            return true
        default:
            return false
        }
    }

    private func handleRemoteTerminalInput(
        terminalID: String,
        data: Data,
        fromPeerID: String?,
        connection: CollaborationRelayConnection
    ) {
        guard peerIsSelectedForHostedTerminal(
            terminalID: terminalID,
            peerID: fromPeerID,
            connection: connection
        ) else { return }
        guard let filteredData = Self.filteredTerminalCollaborationInput(
            data,
            pendingPrefix: &hostedTerminalInputReportPrefixesByID[terminalID, default: Data()],
            direction: "peer-to-host",
            terminalID: terminalID
        ) else { return }
        guard let panel = hostedTerminalsByID[terminalID]?.panel else { return }
        if let peer = peerVisibleToThisClient(fromPeerID, in: connection) {
            hostedTerminalOutputCaretSuppressionsByID[terminalID] = TerminalOutputCaretSuppression(
                expiresAt: Date().addingTimeInterval(1.5)
            )
            panel.surface.hostedView.showTerminalCollaboratorCaret(
                peerID: peer.peerID,
                displayName: peer.displayName,
                colorHex: peer.color
            )
        }
        let text = String(decoding: filteredData, as: UTF8.self)
        switch panel.sendInputResult(text) {
        case .sent:
            panel.surface.forceRefresh(reason: "collaboration.terminalInput")
        case .queued, .inputQueueFull, .surfaceUnavailable, .processExited:
            break
        }
    }

    private static func filteredTerminalCollaborationInput(
        _ data: Data,
        pendingPrefix: inout Data,
        direction: String,
        terminalID: String
    ) -> Data? {
        guard !data.isEmpty || !pendingPrefix.isEmpty else { return nil }
        #if DEBUG
        let originalPendingCount = pendingPrefix.count
        cmuxDebugLog(
            "collab.terminal.input.raw direction=\(direction) terminal=\(terminalID) " +
            "pending=\(originalPendingCount) data=\(debugByteSummary(data))"
        )
        #endif
        var bytes = [UInt8]()
        bytes.reserveCapacity(pendingPrefix.count + data.count)
        bytes.append(contentsOf: pendingPrefix)
        bytes.append(contentsOf: data)
        pendingPrefix = Data()
        var filtered: [UInt8] = []
        filtered.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if let prefixLength = incompleteTerminalGeneratedReportPrefixLength(bytes, from: index) {
                pendingPrefix = Data(bytes[index..<(index + prefixLength)])
                #if DEBUG
                cmuxDebugLog(
                    "collab.terminal.input.buffer direction=\(direction) terminal=\(terminalID) " +
                    "prefix=\(debugByteSummary(pendingPrefix))"
                )
                #endif
                break
            } else if let keyboardInput = terminalKeyboardInputReplacement(bytes, from: index) {
                #if DEBUG
                let sequence = Data(bytes[index..<(index + keyboardInput.length)])
                cmuxDebugLog(
                    "collab.terminal.input.normalize direction=\(direction) terminal=\(terminalID) " +
                    "sequence=\(debugByteSummary(sequence)) replacement=\(debugByteSummary(keyboardInput.replacement))"
                )
                #endif
                filtered.append(contentsOf: keyboardInput.replacement)
                index += keyboardInput.length
                continue
            } else if let reportLength = terminalGeneratedReportLength(bytes, from: index) {
                #if DEBUG
                let report = Data(bytes[index..<(index + reportLength)])
                cmuxDebugLog(
                    "collab.terminal.input.drop direction=\(direction) terminal=\(terminalID) " +
                    "report=\(debugByteSummary(report))"
                )
                #endif
                index += reportLength
                continue
            }
            filtered.append(bytes[index])
            index += 1
        }
        let filteredData = filtered.isEmpty ? nil : Data(filtered)
        #if DEBUG
        cmuxDebugLog(
            "collab.terminal.input.forward direction=\(direction) terminal=\(terminalID) " +
            "data=\(debugByteSummary(filteredData ?? Data())) pending=\(pendingPrefix.count)"
        )
        #endif
        return filteredData
    }

    private static func incompleteTerminalGeneratedReportPrefixLength(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count, bytes[start] == 0x1B else { return nil }
        if start + 1 == bytes.count { return 1 }
        let second = bytes[start + 1]
        if second == 0x5D || second == 0x50 || second == 0x5E || second == 0x5F {
            return stringControlSequenceLength(bytes, from: start) == nil ? (bytes.count - start) : nil
        }
        guard second == 0x5B else { return nil }
        if start + 2 == bytes.count { return 2 }

        var index = start + 2
        if bytes[index] == 0x3F {
            index += 1
            if index == bytes.count { return bytes.count - start }
        }
        while index < bytes.count {
            let byte = bytes[index]
            if (0x20...0x3F).contains(byte) {
                index += 1
                continue
            }
            return nil
        }
        return bytes.count - start
    }

    private static func terminalKeyboardInputReplacement(
        _ bytes: [UInt8],
        from start: Int
    ) -> (length: Int, replacement: Data)? {
        guard start + 3 < bytes.count,
              bytes[start] == 0x1B,
              bytes[start + 1] == 0x5B else {
            return nil
        }

        var index = start + 2
        let parameterStart = index
        while index < bytes.count, (0x30...0x3F).contains(bytes[index]) {
            index += 1
        }
        guard index > parameterStart,
              index < bytes.count,
              bytes[index] == 0x75 else {
            return nil
        }

        let parameterBytes = bytes[parameterStart..<index]
        let parameterString = String(decoding: parameterBytes, as: UTF8.self)
        let parts = parameterString.split(separator: ";")
        guard parts.count >= 2,
              let codepoint = Int(parts[0]),
              let modifiers = Int(parts[1]),
              Self.csiUModifiersContainControl(modifiers),
              let controlByte = Self.controlByte(forCSIUCodepoint: codepoint) else {
            return nil
        }
        return (index - start + 1, Data([controlByte]))
    }

    private static func csiUModifiersContainControl(_ modifiers: Int) -> Bool {
        switch modifiers {
        case 5, 6, 7, 8:
            return true
        default:
            return false
        }
    }

    private static func controlByte(forCSIUCodepoint codepoint: Int) -> UInt8? {
        switch codepoint {
        case 64:
            return 0
        case 65...90:
            return UInt8(codepoint - 64)
        case 91...95:
            return UInt8(codepoint - 64)
        case 97...122:
            return UInt8(codepoint - 96)
        default:
            return nil
        }
    }

    private static func terminalGeneratedReportLength(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start + 1 < bytes.count,
              bytes[start] == 0x1B else {
            return nil
        }
        switch bytes[start + 1] {
        case 0x63:
            return 2
        case 0x5D, 0x50, 0x5E, 0x5F:
            return stringControlSequenceLength(bytes, from: start)
        case 0x5B:
            break
        default:
            return nil
        }
        guard start + 2 < bytes.count else { return nil }

        let first = bytes[start + 2]
        if first == 0x49 || first == 0x4F {
            return 3
        }

        var index = start + 2
        let parameterStart = index
        while index < bytes.count {
            let byte = bytes[index]
            if (0x30...0x3F).contains(byte) {
                index += 1
                continue
            }
            break
        }
        let intermediateStart = index
        while index < bytes.count {
            let byte = bytes[index]
            if (0x20...0x2F).contains(byte) {
                index += 1
                continue
            }
            break
        }
        if index < bytes.count {
            let final = bytes[index]
            guard (0x40...0x7E).contains(final) else { return nil }
            let hasParameters = intermediateStart > parameterStart
            let intermediates = bytes[intermediateStart..<index]
            switch final {
            case 0x52, 0x63, 0x6E:
                return hasParameters ? (index - start + 1) : nil
            case 0x79:
                return intermediates.contains(0x24) ? (index - start + 1) : nil
            default:
                return nil
            }
        } else {
            return nil
        }
    }

    private static func stringControlSequenceLength(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start + 1 < bytes.count else { return nil }
        var index = start + 2
        while index < bytes.count {
            if bytes[index] == 0x07 {
                return index - start + 1
            }
            if index + 1 < bytes.count,
               bytes[index] == 0x1B,
               bytes[index + 1] == 0x5C {
                return index - start + 2
            }
            index += 1
        }
        return nil
    }

    #if DEBUG
    private static func debugByteSummary(_ data: Data) -> String {
        guard !data.isEmpty else { return "empty" }
        let bytes = [UInt8](data.prefix(96))
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let escaped = bytes.map { byte -> String in
            switch byte {
            case 0x1B:
                return "ESC"
            case 0x0D:
                return "CR"
            case 0x0A:
                return "LF"
            case 0x09:
                return "TAB"
            case 0x20...0x7E:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "\\x%02X", byte)
            }
        }.joined()
        let suffix = data.count > bytes.count ? "..." : ""
        return "len=\(data.count) hex=[\(hex)\(suffix)] text='\(escaped)\(suffix)'"
    }
    #endif

    private func handleRemoteTerminalPointer(
        _ pointer: CollaborationTerminalPointerWire,
        connection: CollaborationRelayConnection
    ) {
        guard let peer = peerVisibleToThisClient(pointer.fromPeerID, in: connection) else { return }
        let panels = [
            hostedTerminalsByID[pointer.terminalID]?.panel,
            mirroredTerminalsByID[pointer.terminalID]?.panel
        ].compactMap { $0 }

        for panel in panels {
            panel.surface.hostedView.showTerminalCollaboratorPointer(
                peerID: peer.peerID,
                displayName: peer.displayName,
                colorHex: peer.color,
                normalizedX: pointer.x,
                normalizedY: pointer.y,
                row: pointer.row,
                column: pointer.column,
                contentRow: pointer.contentRow,
                contentRowFromBottom: pointer.contentRowFromBottom,
                visible: pointer.visible,
                coordinateSpace: pointer.coordinateSpace
            )
        }
    }

    private func handleRemoteTerminalSelection(
        _ selection: CollaborationTerminalSelectionWire,
        connection: CollaborationRelayConnection
    ) {
        guard let peer = peerVisibleToThisClient(selection.fromPeerID, in: connection) else { return }
        let panels = [
            hostedTerminalsByID[selection.terminalID]?.panel,
            mirroredTerminalsByID[selection.terminalID]?.panel
        ].compactMap { $0 }

        let rects = selection.rects.map {
            TerminalCollaboratorSelectionRect(
                normalizedRect: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height),
                row: $0.row,
                column: $0.column,
                rowFromBottom: $0.rowFromBottom,
                widthColumns: $0.widthColumns,
                heightRows: $0.heightRows
            )
        }
        for panel in panels {
            panel.surface.hostedView.showTerminalCollaboratorSelection(
                peerID: peer.peerID,
                colorHex: peer.color,
                selectionRects: rects,
                visible: selection.visible
            )
        }
    }

    private func handleRemoteTerminalClose(terminalID: String) {
        mirroredTerminalsByID.removeValue(forKey: terminalID)
        hostedTerminalsByID.removeValue(forKey: terminalID)
        removeTerminalSurfaceMappings(for: terminalID)
        hostedTerminalOutputSequencesByID.removeValue(forKey: terminalID)
        hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridPatchSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridSequencesByID.removeValue(forKey: terminalID)
        terminalStatesByID.removeValue(forKey: terminalID)
        terminalSessionRouter.remove(terminalID: terminalID)
    }

    private func handle(event: CollaborationEvent, sessionCode: String) async {
        guard let connection = connectionsBySessionCode[sessionCode] else { return }
        switch event {
        case .documentChanged(let snapshot):
            guard let panel = panelsByDocumentID[snapshot.documentID]?.panel else { return }
            panel.applyCollaborationText(snapshot.text)
            updateState(documentID: snapshot.documentID, isShared: true, connection: connection)
        case .presenceChanged:
            refreshPeerSummaries(for: connection)
        case .presenceCleared(let peerID):
            connection.peersByID.removeValue(forKey: peerID)
            refreshPeerSummaries(for: connection)
        case .connectionChanged(let state):
            connection.connectionLabel = label(for: state)
            if self.sessionCode == sessionCode {
                connectionLabel = connection.connectionLabel
            }
        case .diskReconciled:
            break
        }
    }

    private func receiveNextMessage(for connection: CollaborationRelayConnection) {
        guard let task = connection.webSocketTask else { return }
        let sessionCode = connection.sessionCode
        task.receive { [weak self] result in
            Task { @MainActor in
                await self?.handleReceive(result, sessionCode: sessionCode)
            }
        }
    }

    private func handleReceive(
        _ result: Result<URLSessionWebSocketTask.Message, Error>,
        sessionCode: String
    ) async {
        guard let connection = connectionsBySessionCode[sessionCode] else { return }
        switch result {
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
            connection.connectionLabel = CollaborationStrings.disconnected
            if self.sessionCode == sessionCode {
                connectionLabel = CollaborationStrings.disconnected
            }
            await connection.session.markDisconnected()
        case .success(let message):
            do {
                let data: Data
                switch message {
                case .string(let string):
                    data = Data(string.utf8)
                case .data(let frameData):
                    data = frameData
                @unknown default:
                    receiveNextMessage(for: connection)
                    return
                }
                try await handleFrameData(data, connection: connection)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            receiveNextMessage(for: connection)
        }
    }

    private func handleFrameData(
        _ data: Data,
        connection: CollaborationRelayConnection
    ) async throws {
        let frameType = try decoder.decode(CollaborationFrameType.self, from: data)
        switch frameType.type {
        case "session.joined":
            let joined = try decoder.decode(CollaborationJoinedWire.self, from: data)
            connection.peersByID = Dictionary(uniqueKeysWithValues: joined.peers.filter { $0.peerID != peerIdentity.peerID }.map { ($0.peerID, $0) })
            refreshPeerSummaries(for: connection)
        case "peer.joined":
            let peer = try decoder.decode(CollaborationPeerJoinedWire.self, from: data).peer
            if peer.peerID != peerIdentity.peerID {
                connection.peersByID[peer.peerID] = peer
                refreshPeerSummaries(for: connection)
                sendHostedTerminalSeedsForNewPeer(peer, via: connection)
            }
        case "peer.left":
            let left = try decoder.decode(CollaborationPeerLeftWire.self, from: data)
            connection.peersByID.removeValue(forKey: left.peerID)
            refreshPeerSummaries(for: connection)
            try await connection.session.applyRemoteFrame(.peerLeft(peerID: left.peerID))
        case "document.update":
            let update = try decoder.decode(CollaborationDocumentUpdateWire.self, from: data)
            try await connection.session.applyRemoteFrame(.documentUpdate(
                documentID: update.documentID,
                updateID: update.updateID,
                operations: update.operations
            ))
        case "document.snapshot":
            let snapshot = try decoder.decode(CollaborationDocumentSnapshotWire.self, from: data)
            snapshotFallbackTasks[snapshot.documentID]?.cancel()
            snapshotFallbackTasks.removeValue(forKey: snapshot.documentID)
            try await connection.session.applyRemoteFrame(.documentSnapshot(
                documentID: snapshot.documentID,
                requestID: snapshot.requestID,
                operations: snapshot.operations,
                textHash: snapshot.textHash
            ))
        case "document.snapshot.request":
            let request = try decoder.decode(CollaborationDocumentSnapshotRequestWire.self, from: data)
            if let descriptor = descriptorsByDocumentID[request.documentID] {
                try await send(
                    try await connection.session.snapshotFrame(for: descriptor, requestID: request.requestID),
                    via: connection
                )
            }
        case "presence.update":
            let presence = try decoder.decode(CollaborationPresenceWire.self, from: data)
            try await connection.session.applyRemoteFrame(.presence(presence.presenceState))
        case "terminal.open":
            let open = try decoder.decode(CollaborationTerminalOpenWire.self, from: data)
            handleRemoteTerminalOpen(
                terminalID: open.terminalID,
                descriptor: open.descriptor,
                ownerPeerID: open.fromPeerID,
                connection: connection
            )
        case "terminal.output":
            let output = try decoder.decode(CollaborationTerminalOutputWire.self, from: data)
            if let bytes = Data(base64Encoded: output.dataBase64) {
                handleRemoteTerminalOutput(
                    terminalID: output.terminalID,
                    sequence: output.sequence,
                    data: bytes,
                    caretPeerID: output.caretPeerID,
                    connection: connection
                )
            }
        case "terminal.render_grid":
            let renderGrid = try decoder.decode(CollaborationTerminalRenderGridWire.self, from: data)
            handleRemoteTerminalRenderGrid(terminalID: renderGrid.terminalID, frame: renderGrid.frame)
        case "terminal.input":
            let input = try decoder.decode(CollaborationTerminalInputWire.self, from: data)
            if let bytes = Data(base64Encoded: input.dataBase64) {
                handleRemoteTerminalInput(
                    terminalID: input.terminalID,
                    data: bytes,
                    fromPeerID: input.fromPeerID,
                    connection: connection
                )
            }
        case "terminal.pointer":
            let pointer = try decoder.decode(CollaborationTerminalPointerWire.self, from: data)
            handleRemoteTerminalPointer(pointer, connection: connection)
        case "terminal.selection":
            let selection = try decoder.decode(CollaborationTerminalSelectionWire.self, from: data)
            handleRemoteTerminalSelection(selection, connection: connection)
        case "terminal.close":
            let close = try decoder.decode(CollaborationTerminalCloseWire.self, from: data)
            handleRemoteTerminalClose(terminalID: close.terminalID)
        case "agent.room.event":
            let wire = try decoder.decode(CollaborationAgentRoomEventWire.self, from: data)
            let room = await agentRoomStore.apply(event: wire.event)
            cacheAgentRoom(room)
            latestAgentRoomID = wire.event.roomID
        case "agent.room.snapshot":
            let wire = try decoder.decode(CollaborationAgentRoomSnapshotWire.self, from: data)
            await agentRoomStore.apply(snapshot: wire.room)
            cacheAgentRoom(wire.room)
            latestAgentRoomID = wire.room.id
        case "agent.room.snapshot.request":
            let wire = try decoder.decode(CollaborationAgentRoomSnapshotRequestWire.self, from: data)
            if let room = await agentRoomStore.room(id: wire.roomID) {
                try await send(CollaborationAgentRoomSnapshotWire(
                    type: "agent.room.snapshot",
                    room: room,
                    requestID: wire.requestID
                ), via: connection)
            }
        case "agent.room.cursor_ack":
            let wire = try decoder.decode(CollaborationAgentRoomCursorAckWire.self, from: data)
            if let room = await agentRoomStore.acknowledge(roomID: wire.roomID, memberID: wire.memberID, sequence: wire.sequence) {
                cacheAgentRoom(room)
            }
        default:
            break
        }
    }

    private func sendTerminalRenderGridSnapshotIfPossible(
        terminalID: String,
        scrollbackLines: Int,
        full: Bool,
        requireLiveScrollbackBottom: Bool,
        recipientParticipantIDs: [String]? = nil,
        via connection: CollaborationRelayConnection
    ) async throws {
        guard let panel = hostedTerminalsByID[terminalID]?.panel else { return }
        guard !requireLiveScrollbackBottom || Self.shouldSendTerminalRenderGridSnapshot(for: panel) else { return }
        let stateSeq = hostedTerminalOutputSequencesByID[terminalID]
            ?? MobileTerminalByteTee.shared.currentSequence(surfaceID: panel.id)
            ?? 0
        guard let snapshot = panel.surface.mobileRenderGridFrame(
            stateSeq: stateSeq,
            full: full,
            scrollbackLines: scrollbackLines
        ) else { return }
        try await send(CollaborationTerminalRenderGridWire(
            type: "terminal.render_grid",
            terminalID: terminalID,
            frame: snapshot.frame,
            recipientParticipantIDs: recipientParticipantIDs ?? recipientParticipantIDsForSending(
                terminalID: terminalID,
                connection: connection
            )
        ), via: connection)
    }

    private func sendHostedTerminalSeedsForNewPeer(
        _ peer: CollaborationPeerWire,
        via connection: CollaborationRelayConnection
    ) {
        let terminals = hostedTerminalsByID.compactMap { terminalID, weakPanel -> (String, TerminalPanel)? in
            guard let panel = weakPanel.panel else { return nil }
            return (terminalID, panel)
        }
        guard !terminals.isEmpty else { return }
        Task {
            for (terminalID, panel) in terminals {
                guard terminalSessionRouter.sessionCode(forTerminalID: terminalID) == connection.sessionCode else {
                    continue
                }
                let recipientID = peer.stableParticipantID
                guard selectedRecipientParticipantIDs(for: terminalID, connection: connection).contains(recipientID) else {
                    continue
                }
                let recipients = [recipientID]
                try? await send(CollaborationTerminalOpenWire(
                    type: "terminal.open",
                    terminalID: terminalID,
                    descriptor: terminalDescriptor(for: panel),
                    recipientParticipantIDs: recipients
                ), via: connection)
                try? await sendTerminalRenderGridSnapshotIfPossible(
                    terminalID: terminalID,
                    scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                    full: true,
                    requireLiveScrollbackBottom: false,
                    recipientParticipantIDs: recipients,
                    via: connection
                )
            }
        }
    }

    private static func shouldSendTerminalRenderGridSnapshot(for panel: TerminalPanel) -> Bool {
        panel.surface.hostedView.isAtLiveScrollbackBottom
    }

    private func scheduleTerminalRenderGridSnapshot(terminalID: String) {
        guard hostedTerminalRenderGridSnapshotTasksByID[terminalID] == nil else { return }
        hostedTerminalRenderGridSnapshotTasksByID[terminalID] = Task { [weak self] in
            await Task.yield()
            if !Task.isCancelled {
                if let connection = await self?.connection(forTerminalID: terminalID) {
                    try? await self?.sendTerminalRenderGridSnapshotIfPossible(
                        terminalID: terminalID,
                        scrollbackLines: Self.terminalLiveRenderGridScrollbackLines,
                        full: false,
                        requireLiveScrollbackBottom: true,
                        via: connection
                    )
                }
            }
            await MainActor.run {
                self?.hostedTerminalRenderGridSnapshotTasksByID.removeValue(forKey: terminalID)
            }
        }
    }

    private func send(_ frame: CollaborationRelayFrame) async throws {
        guard let connection = activeConnection else { throw CollaborationRuntimeError.notConnected }
        try await send(frame, via: connection)
    }

    private func send(_ frame: CollaborationRelayFrame, via connection: CollaborationRelayConnection) async throws {
        switch frame {
        case .documentUpdate(let documentID, let updateID, let operations):
            try await send(CollaborationDocumentUpdateWire(
                type: "document.update",
                documentID: documentID,
                updateID: updateID,
                operations: operations
            ), via: connection)
        case .documentSnapshot(let documentID, let requestID, let operations, let textHash):
            try await send(CollaborationDocumentSnapshotWire(
                type: "document.snapshot",
                documentID: documentID,
                requestID: requestID,
                operations: operations,
                textHash: textHash
            ), via: connection)
        case .documentSnapshotRequest(let documentID, let requestID):
            try await sendSnapshotRequest(documentID: documentID, requestID: requestID, via: connection)
        case .presence(let state):
            try await send(CollaborationPresenceWire(state: state), via: connection)
        case .terminalOpen(let terminalID, let descriptor):
            try await send(CollaborationTerminalOpenWire(
                type: "terminal.open",
                terminalID: terminalID,
                descriptor: descriptor,
                recipientParticipantIDs: recipientParticipantIDsForSending(
                    terminalID: terminalID,
                    connection: connection
                )
            ), via: connection)
        case .terminalOutput(let terminalID, let sequence, let data):
            let caretPeerID = terminalOutputPeerID(for: terminalID)
            try await send(CollaborationTerminalOutputWire(
                type: "terminal.output",
                terminalID: terminalID,
                sequence: sequence,
                dataBase64: data.base64EncodedString(),
                caretPeerID: caretPeerID,
                recipientParticipantIDs: recipientParticipantIDsForSending(
                    terminalID: terminalID,
                    connection: connection
                )
            ), via: connection)
        case .terminalInput(let terminalID, let inputID, let data):
            try await send(CollaborationTerminalInputWire(
                type: "terminal.input",
                terminalID: terminalID,
                inputID: inputID,
                dataBase64: data.base64EncodedString(),
                fromPeerID: peerIdentity.peerID,
                recipientParticipantIDs: recipientParticipantIDsForSending(
                    terminalID: terminalID,
                    connection: connection
                )
            ), via: connection)
        case .terminalClose(let terminalID):
            try await send(CollaborationTerminalCloseWire(
                type: "terminal.close",
                terminalID: terminalID,
                recipientParticipantIDs: recipientParticipantIDsForSending(
                    terminalID: terminalID,
                    connection: connection
                )
            ), via: connection)
        case .agentRoomEvent(let event):
            try await send(CollaborationAgentRoomEventWire(type: "agent.room.event", event: event), via: connection)
        case .agentRoomSnapshot(let room):
            try await send(CollaborationAgentRoomSnapshotWire(type: "agent.room.snapshot", room: room, requestID: nil), via: connection)
        case .agentRoomSnapshotRequest(let roomID, let requestID):
            try await send(CollaborationAgentRoomSnapshotRequestWire(
                type: "agent.room.snapshot.request",
                roomID: roomID,
                requestID: requestID
            ), via: connection)
        case .agentRoomCursorAck(let roomID, let memberID, let sequence):
            try await send(CollaborationAgentRoomCursorAckWire(
                type: "agent.room.cursor_ack",
                roomID: roomID,
                memberID: memberID,
                sequence: sequence
            ), via: connection)
        case .peerLeft:
            break
        }
    }

    private func sendSnapshotRequest(
        documentID: String,
        requestID: String,
        via connection: CollaborationRelayConnection
    ) async throws {
        try await send(CollaborationDocumentSnapshotRequestWire(
            type: "document.snapshot.request",
            documentID: documentID,
            requestID: requestID
        ), via: connection)
    }

    private func send<T: Encodable>(_ frame: T) async throws {
        guard let connection = activeConnection else { throw CollaborationRuntimeError.notConnected }
        try await send(frame, via: connection)
    }

    private func send<T: Encodable>(_ frame: T, via connection: CollaborationRelayConnection) async throws {
        guard let webSocketTask = connection.webSocketTask else { throw CollaborationRuntimeError.notConnected }
        let data = try encoder.encode(frame)
        let text = String(decoding: data, as: UTF8.self)
        try await webSocketTask.send(.string(text))
    }

    private func startHeartbeatLoop(for connection: CollaborationRelayConnection) {
        connection.heartbeatTask?.cancel()
        connection.heartbeatTask = Task { [weak self, weak connection] in
            while !Task.isCancelled {
                guard let connection else { return }
                do {
                    try await self?.send(CollaborationHeartbeatWire(), via: connection)
                    // Collaboration relay expires peers after 30 seconds; 10 seconds tolerates missed beats.
                    try await Task.sleep(for: .seconds(10))
                } catch is CancellationError {
                    return
                } catch {
                    await self?.recordHeartbeatFailure(error)
                    return
                }
            }
        }
    }

    private func recordHeartbeatFailure(_ error: any Error) {
        lastErrorMessage = error.localizedDescription
    }

    private func updateState(
        documentID: String,
        isShared: Bool,
        connection: CollaborationRelayConnection
    ) {
        statesByDocumentID[documentID] = CollaborationDocumentHeaderState(
            isShared: isShared,
            statusText: isShared ? CollaborationStrings.shared : connection.connectionLabel,
            peerSummary: connection.peerSummary
        )
    }

    private func refreshPeerSummaries(for connection: CollaborationRelayConnection) {
        workspaceParticipantSnapshotRevision &+= 1
        for documentID in statesByDocumentID.keys {
            guard sessionCodesByDocumentID[documentID] == connection.sessionCode else { continue }
            updateState(
                documentID: documentID,
                isShared: statesByDocumentID[documentID]?.isShared ?? false,
                connection: connection
            )
        }
        for terminalID in terminalStatesByID.keys {
            guard terminalSessionRouter.sessionCode(forTerminalID: terminalID) == connection.sessionCode else { continue }
            terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
                isShared: terminalStatesByID[terminalID]?.isShared ?? false,
                statusText: terminalStatesByID[terminalID]?.isShared == true ? CollaborationStrings.shared : connection.connectionLabel,
                peerSummary: connection.peerSummary
            )
        }
    }

    private func label(for state: CollaborationConnectionState) -> String {
        switch state {
        case .idle:
            return CollaborationStrings.disconnected
        case .connected:
            return CollaborationStrings.connected
        case .relayUnavailable:
            return CollaborationStrings.connectionFailed
        case .disconnected:
            return CollaborationStrings.disconnected
        case .resynchronizing:
            return CollaborationStrings.resynchronizing
        }
    }

    private func descriptor(for panel: any CollaborationEditablePanel) -> SharedFileDescriptor {
        let root = CollaborationRepositoryResolver.repositoryRoot(for: panel.collaborationFileURL)
        let relativePath: String
        if let root {
            relativePath = panel.collaborationFileURL.path.replacingOccurrences(
                of: root.path.hasSuffix("/") ? root.path : root.path + "/",
                with: ""
            )
        } else {
            relativePath = panel.collaborationFileURL.lastPathComponent
        }
        return SharedFileDescriptor(
            repositoryID: root?.lastPathComponent ?? panel.collaborationFileURL.deletingLastPathComponent().lastPathComponent,
            relativePath: relativePath,
            localURL: panel.collaborationFileURL
        )
    }

    private func terminalDescriptor(for panel: TerminalPanel) -> SharedTerminalDescriptor {
        SharedTerminalDescriptor(
            workspaceID: panel.workspaceId,
            surfaceID: panel.id,
            title: panel.displayTitle
        )
    }

    private func terminalID(for panel: TerminalPanel) -> String {
        if let terminalID = hostedTerminalIDsBySurfaceID[panel.id] ?? mirroredTerminalIDsBySurfaceID[panel.id] {
            return terminalID
        }
        return terminalDescriptor(for: panel).terminalID(sessionID: sessionCode ?? "")
    }

    private func resolveAgentRoomSurfaceID(_ raw: String?) -> UUID? {
        if let raw, let uuid = UUID(uuidString: raw) {
            return uuid
        }
        if let raw, let uuid = agentRoomIDsBySurfaceID.keys.first(where: { $0.uuidString == raw }) {
            return uuid
        }
        if let focused = TerminalController.shared.tabManager?.selectedWorkspace?.focusedTerminalPanel {
            return focused.id
        }
        return TerminalController.shared.tabManager?.tabs
            .lazy
            .flatMap { $0.panels.values }
            .compactMap { ($0 as? TerminalPanel)?.id }
            .first
    }

    private func terminalPanel(surfaceID: UUID) -> TerminalPanel? {
        TerminalController.shared.tabManager?.tabs
            .lazy
            .flatMap { $0.panels.values }
            .compactMap { $0 as? TerminalPanel }
            .first { $0.id == surfaceID }
    }

    private func cacheAgentRoom(_ room: ClaudeRoomSnapshot) {
        agentRoomSnapshotsByID[room.id] = room
    }

    private func cacheAgentRooms(_ rooms: [ClaudeRoomSnapshot]) {
        for room in rooms {
            cacheAgentRoom(room)
        }
    }

    private func agentRoomPayload(_ room: ClaudeRoomSnapshot) -> [String: Any] {
        [
            "room_id": room.id,
            "title": room.title ?? NSNull(),
            "delivery_policy": room.deliveryPolicy.rawValue,
            "last_sequence": room.lastSequence,
            "members": room.members.map(encodedJSONObject),
            "events": room.events.map(encodedJSONObject),
        ]
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return object
    }

    private func disconnectAllConnections() {
        for connection in connectionsBySessionCode.values {
            connection.disconnect()
        }
        connectionsBySessionCode.removeAll()
    }
}

private struct CollaborationPeerJoinedWire: Decodable {
    let peer: CollaborationPeerWire
}

private enum CollaborationRuntimeError: LocalizedError {
    case invalidRelayURL
    case relayRejected
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidRelayURL:
            return CollaborationStrings.invalidRelayURL
        case .relayRejected:
            return CollaborationStrings.relayRejected
        case .notConnected:
            return CollaborationStrings.disconnected
        }
    }
}

private enum CollaborationRepositoryResolver {
    static func repositoryRoot(for fileURL: URL) -> URL? {
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            let gitURL = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

private enum CollaborationTextDiff {
    static func diff(previous: String, next: String) -> (range: Range<Int>, replacement: String) {
        let previousCharacters = Array(previous)
        let nextCharacters = Array(next)
        var prefix = 0
        while prefix < previousCharacters.count,
              prefix < nextCharacters.count,
              previousCharacters[prefix] == nextCharacters[prefix] {
            prefix += 1
        }
        var previousSuffix = previousCharacters.count
        var nextSuffix = nextCharacters.count
        while previousSuffix > prefix,
              nextSuffix > prefix,
              previousCharacters[previousSuffix - 1] == nextCharacters[nextSuffix - 1] {
            previousSuffix -= 1
            nextSuffix -= 1
        }
        return (prefix..<previousSuffix, String(nextCharacters[prefix..<nextSuffix]))
    }
}

enum CollaborationStrings {
    static var collaborate: String {
        String(localized: "collaboration.toolbar.collaborate", defaultValue: "Collaborate")
    }

    static var shareTerminal: String {
        String(localized: "collaboration.terminal.share", defaultValue: "Share Terminal")
    }

    static var manageTerminalSharing: String {
        String(localized: "collaboration.terminal.manageSharing", defaultValue: "Manage Terminal Sharing")
    }

    static var terminalRecipientsTitle: String {
        String(localized: "collaboration.terminal.recipients.title", defaultValue: "Share with")
    }

    static var terminalRecipientsEmpty: String {
        String(
            localized: "collaboration.terminal.recipients.empty",
            defaultValue: "Invite someone to this session, then choose who can view this terminal."
        )
    }

    static var copyInviteCode: String {
        String(localized: "collaboration.action.copyInviteCode", defaultValue: "Copy Invite Code")
    }

    static var share: String {
        String(localized: "collaboration.action.share", defaultValue: "Share")
    }

    static var connectClaudeRoom: String {
        String(localized: "collaboration.agentRoom.connect", defaultValue: "Connect Claude Room")
    }

    static var agentRoomConnectedFormat: String {
        String(localized: "collaboration.agentRoom.connectedFormat", defaultValue: "Claude room %@")
    }

    static var stopSharingTerminal: String {
        String(localized: "collaboration.terminal.stopSharing", defaultValue: "Stop Sharing Terminal")
    }

    static var sharedTerminalTitle: String {
        String(localized: "collaboration.terminal.sharedTitle", defaultValue: "Shared Terminal")
    }

    static var noWorkspaceForTerminalShare: String {
        String(localized: "collaboration.terminal.error.noWorkspace", defaultValue: "No workspace is available for the shared terminal.")
    }

    static var terminalShareFailed: String {
        String(localized: "collaboration.terminal.error.shareFailed", defaultValue: "Could not create the shared terminal mirror.")
    }

    static var shared: String {
        String(localized: "collaboration.status.shared", defaultValue: "Shared")
    }

    static var disconnected: String {
        String(localized: "collaboration.status.disconnected", defaultValue: "Not connected")
    }

    static var connecting: String {
        String(localized: "collaboration.status.connecting", defaultValue: "Connecting...")
    }

    static var connected: String {
        String(localized: "collaboration.status.connected", defaultValue: "Connected")
    }

    static var connectionFailed: String {
        String(localized: "collaboration.status.connectionFailed", defaultValue: "Connection failed")
    }

    static var resynchronizing: String {
        String(localized: "collaboration.status.resynchronizing", defaultValue: "Resynchronizing")
    }

    static var noPeers: String {
        String(localized: "collaboration.peers.none", defaultValue: "No peers")
    }

    static var onePeer: String {
        String(localized: "collaboration.peers.one", defaultValue: "1 peer")
    }

    static var peerCountFormat: String {
        String(localized: "collaboration.peers.count", defaultValue: "%d peers")
    }

    static var startTitle: String {
        String(localized: "collaboration.start.title", defaultValue: "Start Collaboration")
    }

    static var startMessage: String {
        String(localized: "collaboration.start.message", defaultValue: "Create a new invite or join one with a session code.")
    }

    static var relayURLPlaceholder: String {
        String(localized: "collaboration.relay.urlPlaceholder", defaultValue: "Relay URL")
    }

    static var createSession: String {
        String(localized: "collaboration.action.createSession", defaultValue: "Create Session")
    }

    static var joinSession: String {
        String(localized: "collaboration.action.joinSession", defaultValue: "Join Session")
    }

    static var cancel: String {
        String(localized: "collaboration.action.cancel", defaultValue: "Cancel")
    }

    static var done: String {
        String(localized: "collaboration.action.done", defaultValue: "Done")
    }

    static var copyCode: String {
        String(localized: "collaboration.action.copyCode", defaultValue: "Copy Code")
    }

    static var sessionCreatedTitle: String {
        String(localized: "collaboration.created.title", defaultValue: "Session Created")
    }

    static func sessionCreatedMessage(code: String) -> String {
        let format = String(
            localized: "collaboration.created.message",
            defaultValue: "Share this session code with collaborators: %@"
        )
        return String(format: format, code)
    }

    static var joinMessage: String {
        String(localized: "collaboration.join.message", defaultValue: "Enter the session code from the collaborator.")
    }

    static var sessionCodePlaceholder: String {
        String(localized: "collaboration.join.sessionCodePlaceholder", defaultValue: "Session code")
    }

    static var invalidRelayURL: String {
        String(localized: "collaboration.error.invalidRelayURL", defaultValue: "Invalid relay URL.")
    }

    static var relayRejected: String {
        String(localized: "collaboration.error.relayRejected", defaultValue: "The relay rejected the request.")
    }
}

struct CollaborationHeaderControls<PanelModel>: View where PanelModel: CollaborationEditablePanel {
    @State private var runtime = CollaborationRuntime.shared
    let panel: PanelModel

    var body: some View {
        let state = runtime.state(for: panel)
        HStack(spacing: 6) {
            if state.isShared {
                Text(state.peerSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            PanelHeaderIconButton(
                systemName: state.isShared ? "person.2.fill" : "person.2",
                label: state.isShared ? "\(state.statusText) - \(state.peerSummary)" : CollaborationStrings.collaborate,
                isDisabled: false,
                action: {
                    if state.isShared {
                        runtime.leave(panel: panel)
                    } else {
                        runtime.configureOrShare(panel: panel)
                    }
                }
            )
        }
    }
}
