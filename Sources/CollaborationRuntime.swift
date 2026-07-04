import AppKit
import CMUXMobileCore
import CmuxCollaboration
import CmuxFoundation
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
    var isConnectedToSession = false
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
    let imageURL: String?

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
    let viewportRowFromBottom: Double?
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

private struct TerminalGridSize: Equatable {
    let columns: Int
    let rows: Int
}

private struct CollaborationTerminalDimensionsWire: Codable {
    let type: String
    let terminalID: String
    let columns: Int
    let rows: Int
    let recipientParticipantIDs: [String]?

    init(type: String, terminalID: String, columns: Int, rows: Int, recipientParticipantIDs: [String]? = nil) {
        self.type = type
        self.terminalID = terminalID
        self.columns = columns
        self.rows = rows
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
    var isHosted = false
    var isMirrored = false
    var statusText = ""
    var peerSummary = ""
    var ownerSnapshot: CollaborationParticipantAvatarSnapshot?
    var workspaceSessionCode: String?
    var isWorkspaceSessionConnected = false

    var sharingRole: CollaborationSurfaceSharingRole {
        if isHosted { return .hosted }
        if isMirrored { return .mirrored }
        return .notShared
    }
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

private final class AgentRoomWireAnchor {
    let screenPoint: NSPoint
    weak var window: NSWindow?
    let ownerID: ObjectIdentifier

    init(screenPoint: NSPoint, window: NSWindow?, ownerID: ObjectIdentifier) {
        self.screenPoint = screenPoint
        self.window = window
        self.ownerID = ownerID
    }
}

@MainActor
private final class AgentRoomWireOverlayController {
    private var overlayWindow: NSWindow?
    private var overlayView: AgentRoomWireOverlayView?
    private var timer: Timer?
    private var sourceScreenPoint: NSPoint = .zero

    func start(from sourceScreenPoint: NSPoint, in sourceWindow: NSWindow?) {
        stop()
        guard let sourceWindow else { return }
        self.sourceScreenPoint = sourceScreenPoint

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
        // Re-derive the source point from screen coordinates each tick so the wire
        // stays pinned to the link button even if the overlay window's frame moves.
        overlayView.sourcePoint = overlayView.viewPoint(forScreenPoint: sourceScreenPoint, in: overlayWindow)
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
        shadow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.55)
        shadow.set()
        path.lineWidth = 9
        NSColor.systemBlue.withAlphaComponent(0.35).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        path.lineWidth = 5
        NSColor.systemBlue.setStroke()
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
        NSColor.systemBlue.setFill()
        oval.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        oval.lineWidth = 2
        oval.stroke()
    }
}

private struct CollaborationTerminalOwnerAvatarRenderer {
    private let pixelSize = 48

    func fallbackPNGData(for participant: CollaborationParticipantAvatarSnapshot) -> Data? {
        renderPNG { size in
            let circleRect = NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let circle = NSBezierPath(ovalIn: circleRect)
            (NSColor(hex: participant.colorHex) ?? .controlAccentColor).setFill()
            circle.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(pixelSize) * 0.38, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let initials = NSString(string: participant.initials)
            let textSize = initials.size(withAttributes: attributes)
            let textRect = NSRect(
                x: 0,
                y: (size.height - textSize.height) / 2 - 1,
                width: size.width,
                height: textSize.height
            )
            initials.draw(in: textRect, withAttributes: attributes)
        }
    }

    func profilePNGData(from imageData: Data) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }
        return renderPNG { size in
            let circleRect = NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let clipPath = NSBezierPath(ovalIn: circleRect)
            clipPath.addClip()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: circleRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
    }

    private func renderPNG(_ draw: (NSSize) -> Void) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        let size = NSSize(width: pixelSize, height: pixelSize)
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        draw(size)

        return bitmap.representation(using: .png, properties: [:])
    }
}

private actor CollaborationTerminalOwnerProfileImageCache {
    private static let maximumImageBytes = 4 * 1024 * 1024

    private var cachedDataByURL: [String: Data] = [:]
    private var failedURLs: Set<String> = []

    func imageData(for url: URL) async -> Data? {
        let key = url.absoluteString
        if let cached = cachedDataByURL[key] {
            return cached
        }
        if failedURLs.contains(key) {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                data.count <= Self.maximumImageBytes,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                failedURLs.insert(key)
                return nil
            }
            cachedDataByURL[key] = data
            return data
        } catch {
            failedURLs.insert(key)
            return nil
        }
    }
}

@MainActor
@Observable
final class CollaborationRuntime {
    static let shared = CollaborationRuntime()
    static let agentRoomWirePasteboardTypeIdentifier = "com.cmux.agent-room-wire"
    private static let defaultRelayURLString = "https://cmux-collaboration-worker.dorsa-rohani.workers.dev"
    private static let terminalInitialRenderGridScrollbackLines = 10_000
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
    private(set) var agentRoomHeaderRevision = 0

    private var peerIdentity: CollaborationPeerIdentity
    private let localAvatarSeed: String
    private let terminalOwnerAvatarRenderer = CollaborationTerminalOwnerAvatarRenderer()
    private let terminalOwnerProfileImageCache = CollaborationTerminalOwnerProfileImageCache()
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
    /// Last host grid size broadcast per terminal, so a change is only sent to
    /// peers when the host's grid (columns or rows) actually changes.
    private var hostedTerminalBroadcastGridByID: [String: TerminalGridSize] = [:]
    private var mirroredTerminalsByID: [String: WeakCollaborationTerminalPanel] = [:]
    private var mirroredTerminalIDsBySurfaceID: [UUID: String] = [:]
    private var terminalOwnerParticipantIDsByID: [String: String] = [:]
    private var terminalOwnerAvatarRequestKeysByID: [String: String] = [:]
    private var mirroredTerminalRenderGridPatchSequencesByID: [String: UInt64] = [:]
    private var mirroredTerminalRenderGridSequencesByID: [String: UInt64] = [:]
    private var mirroredTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var hostedTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var terminalStatesByID: [String: CollaborationTerminalHeaderState] = [:]
    private var terminalPointerLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    private var terminalSelectionLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    private var snapshotFallbackTasks: [String: Task<Void, Never>] = [:]
    private var sessionStartedAtBySessionCode: [String: TimeInterval] = [:]
    private var isPresentingStartDialog = false
    private let agentRoomStore = ClaudeRoomStore()
    private let agentRoomDigestBuilder = ClaudeRoomDigestBuilder()
    private var agentRoomIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomMemberIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomSnapshotsByID: [String: ClaudeRoomSnapshot] = [:]
    @ObservationIgnored private var agentRoomWireAnchorsBySurfaceID: [UUID: AgentRoomWireAnchor] = [:]
    @ObservationIgnored private let agentRoomWireOverlay = AgentRoomWireOverlayController()
    @ObservationIgnored private var draggingAgentRoomSourceSurfaceID: UUID?
    @ObservationIgnored private let productAnalytics = ProductAnalytics.shared
    private var latestAgentRoomID: String?
    private let agentRoomActiveDispatchPromptBuilder = AgentRoomActiveDispatchPromptBuilder()
    @ObservationIgnored private var terminalSurfaceReadyObserver: NSObjectProtocol?

    private init() {
        let displayName = NSFullUserName().isEmpty ? Host.current().localizedName ?? "cmux" : NSFullUserName()
        localAvatarSeed = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? displayName
        peerIdentity = CollaborationPeerIdentity.persistedParticipant(displayName: displayName)
        installTerminalSurfaceReadyObserver()
    }

    /// A mirrored terminal's ghostty surface is created lazily on the first AppKit
    /// layout pass, which usually lands after the host's one-shot full render-grid
    /// seed has already arrived. That seed is buffered/applied while the surface is
    /// not yet presentable and is only nudged with an async refresh, so with no
    /// follow-up traffic the pane can sit black until someone types. Force a
    /// synchronous present once the mirror surface actually becomes ready — mirrors
    /// the readiness re-arm that `RemoteTmuxSessionMirror` performs for its manual-IO
    /// display surfaces.
    private func installTerminalSurfaceReadyObserver() {
        terminalSurfaceReadyObserver = NotificationCenter.default.addObserver(
            forName: .terminalSurfaceDidBecomeReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let surfaceID = notification.userInfo?["surfaceId"] as? UUID else { return }
            Task { @MainActor in self?.presentMirroredTerminalIfReady(surfaceID: surfaceID) }
        }
    }

    private func presentMirroredTerminalIfReady(surfaceID: UUID) {
        guard let terminalID = mirroredTerminalIDsBySurfaceID[surfaceID],
              let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        panel.surface.forceRefresh(reason: "collaboration.mirrorReady")
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

    /// Session code scoped to one terminal. Sharing is per-surface: only the
    /// terminal that was actually hosted/mirrored into a session (or whose
    /// workspace explicitly joined a session that is still live) counts as
    /// "in session". Sibling terminals must not inherit another terminal's
    /// share just because they live in the same workspace.
    private func terminalScopedSessionCode(for terminal: TerminalPanel) -> String? {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id] ?? mirroredTerminalIDsBySurfaceID[terminal.id]
        if let terminalID, let code = terminalSessionRouter.sessionCode(forTerminalID: terminalID) {
            return code
        }
        // Workspace bindings come from the explicit join flow. Only honor them
        // while the relay connection is live so stale persisted bindings can't
        // resurrect session UI on unrelated terminals.
        if let code = sessionCode(forWorkspaceID: terminal.workspaceId), connectionsBySessionCode[code] != nil {
            return code
        }
        return nil
    }

    private func terminalHeaderState(
        _ state: CollaborationTerminalHeaderState,
        for terminal: TerminalPanel
    ) -> CollaborationTerminalHeaderState {
        let terminalSessionCode = terminalScopedSessionCode(for: terminal)
        var enriched = state
        enriched.workspaceSessionCode = terminalSessionCode
        enriched.isWorkspaceSessionConnected = terminalSessionCode.flatMap { connectionsBySessionCode[$0] } != nil
        return enriched
    }

    private func recordWorkspaceSession(_ sessionCode: String, workspaceID: UUID) {
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        sessionCodesByWorkspaceID[workspaceID] = normalizedCode
        Self.workspaceSessionStore.record(sessionCode: normalizedCode, forWorkspaceID: workspaceID)
        workspaceParticipantSnapshotRevision &+= 1
        trackCollaborationLayoutSnapshot(reason: "workspace_session_recorded", sessionCode: normalizedCode, workspaceID: workspaceID)
    }

    func participantSnapshots(forWorkspaceID workspaceID: UUID) -> [CollaborationWorkspaceParticipantSnapshot] {
        _ = workspaceParticipantSnapshotRevision
        guard let sessionCode = sessionCode(forWorkspaceID: workspaceID) else {
            return []
        }
        return participantSnapshots(inSession: sessionCode)
    }

    func participantSnapshots(for terminal: TerminalPanel) -> [CollaborationWorkspaceParticipantSnapshot] {
        _ = workspaceParticipantSnapshotRevision
        guard let sessionCode = terminalScopedSessionCode(for: terminal) else {
            return []
        }
        return participantSnapshots(inSession: sessionCode)
    }

    private func participantSnapshots(inSession sessionCode: String) -> [CollaborationWorkspaceParticipantSnapshot] {
        let local = localParticipantSnapshot()
        guard let connection = connectionsBySessionCode[sessionCode] else {
            return [local]
        }
        let peers = connection.peersByID.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { peer in
                CollaborationWorkspaceParticipantSnapshot.remote(
                    peerID: peer.peerID,
                    displayName: peer.displayName,
                    colorHex: peer.color,
                    imageURL: peer.imageURL
                )
            }
        return [local] + peers
    }

    private func localParticipantSnapshot() -> CollaborationParticipantAvatarSnapshot {
        CollaborationParticipantAvatarSnapshot.local(
            identity: peerIdentity,
            avatarSeed: localAvatarSeed
        )
    }

    private func ownerSnapshot(
        forPeerID peerID: String?,
        in connection: CollaborationRelayConnection
    ) -> CollaborationParticipantAvatarSnapshot? {
        guard let peerID else { return nil }
        if peerID == peerIdentity.peerID {
            return localParticipantSnapshot()
        }
        guard let peer = connection.peersByID[peerID] else {
            return CollaborationParticipantAvatarSnapshot.remote(
                peerID: peerID,
                displayName: peerID,
                colorHex: CollaborationPeerIdentity.defaultColorPalette.first ?? "#0A84FF"
            )
        }
        return CollaborationParticipantAvatarSnapshot.remote(
            peerID: peer.peerID,
            displayName: peer.displayName,
            colorHex: peer.color,
            imageURL: peer.imageURL
        )
    }

    private func syncTerminalTabPresentation(
        terminalID: String,
        ownerSnapshot: CollaborationParticipantAvatarSnapshot?
    ) {
        guard let panel = hostedTerminalsByID[terminalID]?.panel ?? mirroredTerminalsByID[terminalID]?.panel else {
            return
        }
        guard let workspace = TerminalController.shared.tabManager?.tabs.first(where: { $0.id == panel.workspaceId }) else {
            return
        }
        let title = ownerSnapshot.map { CollaborationStrings.terminalOwnerTitle(displayName: $0.displayName) }
        let fallbackIconData = ownerSnapshot.flatMap { terminalOwnerAvatarRenderer.fallbackPNGData(for: $0) }
        workspace.setCollaborationTerminalTabPresentation(
            panelId: panel.id,
            title: title,
            iconImageData: fallbackIconData
        )
        guard let ownerSnapshot else {
            terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
            return
        }
        guard case .remoteImage(let profileImageURL) = ownerSnapshot.avatarContent else {
            terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
            return
        }
        let requestKey = "\(ownerSnapshot.peerID)|\(profileImageURL.absoluteString)"
        terminalOwnerAvatarRequestKeysByID[terminalID] = requestKey
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let imageData = await terminalOwnerProfileImageCache.imageData(for: profileImageURL) else { return }
            guard let profileIconData = terminalOwnerAvatarRenderer.profilePNGData(from: imageData) else { return }
            guard terminalOwnerAvatarRequestKeysByID[terminalID] == requestKey else { return }
            guard let panel = hostedTerminalsByID[terminalID]?.panel ?? mirroredTerminalsByID[terminalID]?.panel else {
                return
            }
            guard let workspace = TerminalController.shared.tabManager?.tabs.first(where: { $0.id == panel.workspaceId }) else {
                return
            }
            workspace.setCollaborationTerminalTabPresentation(
                panelId: panel.id,
                title: title,
                iconImageData: profileIconData
            )
        }
    }

    private func restoreAllTerminalTabPresentations() {
        let terminalIDs = Set(hostedTerminalsByID.keys).union(mirroredTerminalsByID.keys)
        for terminalID in terminalIDs {
            syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: nil)
        }
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
            peerSummary: connection?.peerSummary ?? CollaborationStrings.noPeers,
            isConnectedToSession: connection != nil
        )
    }

    func configureOrShare(
        panel: any CollaborationEditablePanel,
        entrypoint: CollaborationAnalyticsEntrypoint = .documentHeaderButton
    ) {
        setSharing(true, for: panel, entrypoint: entrypoint)
    }

    func setSharing(
        _ isSharing: Bool,
        for panel: any CollaborationEditablePanel,
        entrypoint: CollaborationAnalyticsEntrypoint = .documentHeaderButton
    ) {
        let state = state(for: panel)
        if isSharing {
            if state.isShared { return }
            let didRequireSignIn = AppDelegate.shared?.auth?.coordinator.isAuthenticated != true
            let didCreateSession = activeConnection == nil
            PostHogAnalytics.shared.capture("document_sharing_enabled", properties: [
                "required_sign_in": didRequireSignIn,
                "required_session_create": didCreateSession,
            ])
            guard ensureSignedInForCollaboration(continue: { [weak panel] in
                guard let panel else { return }
                self.setSharing(true, for: panel, entrypoint: entrypoint)
            }) else {
                return
            }
            trackCollaboration(
                .shareInitiated,
                shareKind: .document,
                entrypoint: entrypoint,
                result: .started,
                properties: ["workspace_has_session": sessionCode != nil]
            )
            if activeConnection != nil {
                share(panel: panel, entrypoint: entrypoint)
            } else {
                scheduleStartDialog(thenShare: panel)
            }
        } else if state.isShared {
            PostHogAnalytics.shared.capture("document_sharing_disabled")
            leave(panel: panel)
        }
    }

    func state(for terminal: TerminalPanel) -> CollaborationTerminalHeaderState {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id] ?? mirroredTerminalIDsBySurfaceID[terminal.id]
        if let terminalID, let state = terminalStatesByID[terminalID] {
            return terminalHeaderState(state, for: terminal)
        }
        let connection = activeConnection
        return terminalHeaderState(CollaborationTerminalHeaderState(
            isShared: false,
            statusText: connection?.connectionLabel ?? connectionLabel,
            peerSummary: connection?.peerSummary ?? CollaborationStrings.noPeers,
            ownerSnapshot: nil
        ), for: terminal)
    }

    func canManageRecipients(for terminal: TerminalPanel) -> Bool {
        hostedTerminalIDsBySurfaceID[terminal.id] != nil
    }

    func configureOrShare(
        terminal: TerminalPanel,
        entrypoint: CollaborationAnalyticsEntrypoint = .terminalHeaderButton
    ) {
        setSharing(true, for: terminal, entrypoint: entrypoint)
    }

    func setSharing(
        _ isSharing: Bool,
        for terminal: TerminalPanel,
        entrypoint: CollaborationAnalyticsEntrypoint = .terminalHeaderButton
    ) {
        let workspaceSessionCode = terminalScopedSessionCode(for: terminal)
        let currentState = state(for: terminal)
        let role = currentState.sharingRole
        if isSharing {
            switch CollaborationTerminalShareAction.primaryAction(
                role: role,
                workspaceHasSession: workspaceSessionCode != nil
            ) {
            case .presentSessionChooser, .shareInWorkspaceSession:
                guard ensureSignedInForCollaboration(continue: { [weak terminal] in
                    guard let terminal else { return }
                    self.setSharing(true, for: terminal, entrypoint: entrypoint)
                }) else {
                    return
                }
                #if DEBUG
        print("[PostHog] firing: terminal_sharing_started")
        #endif
        PostHogAnalytics.shared.capture("terminal_sharing_started")
                trackCollaboration(
                    .shareInitiated,
                    shareKind: .terminal,
                    entrypoint: entrypoint,
                    result: .started,
                    properties: [
                        "workspace_has_session": workspaceSessionCode != nil,
                        "was_already_shared": currentState.isShared,
                        "can_manage_recipients": canManageRecipients(for: terminal),
                    ]
                )
                switch CollaborationTerminalShareAction.primaryAction(
                    role: role,
                    workspaceHasSession: workspaceSessionCode != nil
                ) {
                case .presentSessionChooser:
                    scheduleStartDialog(thenShare: terminal)
                case .shareInWorkspaceSession:
                    guard let workspaceSessionCode else {
                        scheduleStartDialog(thenShare: terminal)
                        return
                    }
                    if let connection = connectionsBySessionCode[workspaceSessionCode] {
                        sessionCode = workspaceSessionCode
                        connectionLabel = connection.connectionLabel
                        share(terminal: terminal, via: connection, entrypoint: entrypoint)
                        return
                    }
                    Task {
                        if let connection = await joinSession(code: workspaceSessionCode, entrypoint: entrypoint) {
                            share(terminal: terminal, via: connection, entrypoint: entrypoint)
                        }
                    }
                case .stopSharingHostedTerminal, .stopViewingRemoteTerminal, .presentParticipantPicker:
                    break
                }
            case .stopSharingHostedTerminal, .stopViewingRemoteTerminal, .presentParticipantPicker:
                break
            }
        } else {
            switch CollaborationTerminalShareAction.primaryAction(
                role: role,
                workspaceHasSession: workspaceSessionCode != nil
            ) {
            case .stopSharingHostedTerminal, .stopViewingRemoteTerminal:
                leave(terminal: terminal)
            case .presentSessionChooser, .shareInWorkspaceSession, .presentParticipantPicker:
                break
            }
        }
    }

    func ensureSignedInForCollaboration(continue action: @escaping @MainActor () -> Void) -> Bool {
        guard let auth = AppDelegate.shared?.auth else {
            NSSound.beep()
            return false
        }
        if auth.coordinator.isAuthenticated {
            refreshPeerIdentityFromAuth()
            return true
        }

        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.signInRequiredTitle
        let signInButton = alert.addButton(withTitle: CollaborationStrings.signIn)
        styleAccentAlertButtonTitleBlack(signInButton)
        alert.addButton(withTitle: CollaborationStrings.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        Task { @MainActor in
            let signedIn = await auth.browserSignIn.signIn(timeout: 10 * 60)
            guard signedIn else { return }
            refreshPeerIdentityFromAuth()
            action()
        }
        return false
    }

    func refreshPeerIdentityFromCurrentAuth() {
        _ = refreshPeerIdentityFromAuth()
    }

    @discardableResult
    private func refreshPeerIdentityFromAuth() -> Bool {
        guard let user = AppDelegate.shared?.auth?.coordinator.currentUser else { return false }
        let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? user.primaryEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? peerIdentity.displayName
        let nextIdentity = CollaborationPeerIdentity.authenticatedParticipant(
            peerID: peerIdentity.peerID,
            userID: user.id,
            displayName: displayName,
            imageURL: user.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        guard nextIdentity != peerIdentity else { return false }
        peerIdentity = nextIdentity
        workspaceParticipantSnapshotRevision &+= 1
        resyncLocalOwnedTerminalTabPresentations()
        return true
    }

    private func resyncLocalOwnedTerminalTabPresentations() {
        let snapshot = localParticipantSnapshot()
        for terminalID in hostedTerminalsByID.keys {
            terminalOwnerParticipantIDsByID[terminalID] = peerIdentity.participantID
            if var state = terminalStatesByID[terminalID] {
                state.ownerSnapshot = snapshot
                terminalStatesByID[terminalID] = state
            }
            syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: snapshot)
        }
    }

    func recipientSnapshots(for terminal: TerminalPanel) -> [CollaborationTerminalRecipientSnapshot] {
        _ = workspaceParticipantSnapshotRevision
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
        #if DEBUG
        print("[PostHog] firing: invite_code_copied")
        #endif
        PostHogAnalytics.shared.capture("invite_code_copied", properties: [
            "context": "share_terminal_popover",
        ])
        trackCollaboration(
            .inviteCodeCopied,
            shareKind: .terminal,
            entrypoint: .recipientPopover,
            result: .completed
        )
        trackCollaborationLayoutSnapshot(reason: "invite_code_copied", sessionCode: normalizedCode, workspaceID: terminal.workspaceId)
    }

    func createWorkspaceSession(for terminal: TerminalPanel) {
        guard ensureSignedInForCollaboration(continue: { [weak terminal] in
            guard let terminal else { return }
            self.createWorkspaceSession(for: terminal)
        }) else {
            return
        }
        Task { await createSessionAndShare(terminal: terminal) }
    }

    func joinWorkspaceSession(for terminal: TerminalPanel) {
        guard ensureSignedInForCollaboration(continue: { [weak terminal] in
            guard let terminal else { return }
            self.joinWorkspaceSession(for: terminal)
        }) else {
            return
        }
        presentJoinDialog(thenBindWorkspaceFor: terminal)
    }

    func copyWorkspaceSessionInviteCode(for terminal: TerminalPanel) {
        let code = terminalScopedSessionCode(for: terminal) ?? sessionCode
        guard let code else { return }
        let normalizedCode = Self.normalizedSessionCode(from: code)
        guard !normalizedCode.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(normalizedCode, forType: .string)
        #if DEBUG
        print("[PostHog] firing: invite_code_copied")
        #endif
        PostHogAnalytics.shared.capture("invite_code_copied", properties: [
            "context": "share_terminal_popover",
        ])
        trackCollaboration(
            .inviteCodeCopied,
            shareKind: .terminal,
            entrypoint: .recipientPopover,
            result: .completed,
            properties: [
                "session_code_present": true,
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(terminal.workspaceId.uuidString),
            ]
        )
        trackCollaborationLayoutSnapshot(reason: "invite_code_copied", sessionCode: normalizedCode, workspaceID: terminal.workspaceId)
    }

    func leaveWorkspaceSession(for terminal: TerminalPanel) {
        guard let workspaceSessionCode = terminalScopedSessionCode(for: terminal) else { return }
        let normalizedCode = Self.normalizedSessionCode(from: workspaceSessionCode)
        guard !normalizedCode.isEmpty else { return }
        let terminalIDs = terminalStatesByID.keys.filter {
            terminalSessionRouter.sessionCode(forTerminalID: $0) == normalizedCode
        }
        trackCollaborationLayoutSnapshot(reason: "session_left", sessionCode: normalizedCode, workspaceID: terminal.workspaceId)
        for terminalID in terminalIDs {
            leave(terminalID: terminalID)
        }
        trackCollaborationSessionEnded(sessionCode: normalizedCode, reason: "workspace_session_left")
        trackCollaboration(
            .sessionLeft,
            shareKind: .terminal,
            entrypoint: .terminalHeaderButton,
            result: .completed,
            properties: [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(terminal.workspaceId.uuidString),
                "terminal_count": terminalIDs.count,
            ],
            flush: true
        )
        sessionCodesByWorkspaceID.removeValue(forKey: terminal.workspaceId)
        Self.workspaceSessionStore.remove(workspaceID: terminal.workspaceId)
        if let connection = connectionsBySessionCode.removeValue(forKey: normalizedCode) {
            PostHogAnalytics.shared.capture("collaboration_ws_disconnected", properties: [
                "reason": "workspace_session_left",
            ])
            connection.disconnect()
        }
        if sessionCode == normalizedCode {
            sessionCode = nil
            connectionLabel = CollaborationStrings.disconnected
        }
        workspaceParticipantSnapshotRevision &+= 1
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
        // Selection now applies directly from checkbox toggles (no confirm button),
        // so bump the revision to refresh readers like the header's "Shared to N".
        workspaceParticipantSnapshotRevision &+= 1
        trackCollaboration(
            .recipientsUpdated,
            shareKind: .terminal,
            entrypoint: .recipientPopover,
            result: .completed,
            properties: [
                "peer_count": knownIDs.count,
                "recipient_count": nextIDs.count,
                "recipient_count_added": addedIDs.count,
                "recipient_count_removed": removedIDs.count,
            ]
        )
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
                        fromPeerID: peerIdentity.peerID,
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
                broadcastHostedTerminalDimensions(
                    terminalID: terminalID,
                    connection: connection,
                    recipientParticipantIDs: recipients,
                    force: true
                )
            }
        }
    }

    func leave(terminal: TerminalPanel) {
        let terminalID = hostedTerminalIDsBySurfaceID[terminal.id]
            ?? mirroredTerminalIDsBySurfaceID[terminal.id]
            ?? terminalID(for: terminal)
        leave(terminalID: terminalID)
    }

    private func leave(terminalID: String) {
        let connection = connection(forTerminalID: terminalID)
        let sharedToCount = connection.map {
            selectedRecipientParticipantIDs(for: terminalID, connection: $0).count
        } ?? 0
        syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: nil)
        hostedTerminalsByID.removeValue(forKey: terminalID)
        removeTerminalSurfaceMappings(for: terminalID)
        hostedTerminalOutputSequencesByID.removeValue(forKey: terminalID)
        hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        hostedTerminalBroadcastGridByID.removeValue(forKey: terminalID)
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
        trackCollaboration(
            .shareStopped,
            shareKind: .terminal,
            entrypoint: .terminalHeaderButton,
            result: .completed
        )
        #if DEBUG
        print("[PostHog] firing: terminal_sharing_stopped")
        #endif
        PostHogAnalytics.shared.capture("terminal_sharing_stopped", properties: [
            "shared_to_count": sharedToCount,
        ])
        if let connection {
            trackCollaborationLayoutSnapshot(reason: "pane_unshared", sessionCode: connection.sessionCode)
        }
    }

    func noteTerminalOutput(surfaceID: UUID, data: Data) {
        guard let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] else { return }
        let sequence = hostedTerminalOutputSequencesByID[terminalID] ?? 0
        hostedTerminalOutputSequencesByID[terminalID] = sequence &+ UInt64(data.count)
        Task {
            if let connection = connection(forTerminalID: terminalID) {
                // The byte-faithful raw stream is the mirror's sole live painter;
                // it reproduces scrollback, TUIs, and resizes exactly. We do NOT
                // also send a live render-grid delta here: the two transports
                // interleave and desync, which left stale rows on the peer. The
                // render-grid path is used only for the cold-attach full seed.
                try? await send(.terminalOutput(terminalID: terminalID, sequence: sequence, data: data), via: connection)
            }
        }
        // A host resize produces redraw output; piggyback a column re-broadcast
        // so peers re-lock their mirror width when the host grid changes.
        if let connection = connection(forTerminalID: terminalID) {
            broadcastHostedTerminalDimensions(terminalID: terminalID, connection: connection)
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
        viewportRowFromBottom: Double?,
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
                    contentRowFromBottom: contentRowFromBottom,
                    viewportRowFromBottom: viewportRowFromBottom
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
                let gridRect = gridRects.indices.contains(index) ? gridRects[index] : nil
                let clipped = rect.intersection(bounds)
                let hasValidClip = !clipped.isNull && clipped.width > 0 && clipped.height > 0
                // Emit rows scrolled off the host's own viewport too: a row with
                // absolute grid coordinates (rowFromBottom) must still travel so
                // the peer can map it into its own (possibly taller/differently
                // scrolled) viewport. The peer prefers the grid coordinates and
                // ignores the normalized rect when they are present.
                guard hasValidClip || gridRect?.rowFromBottom != nil else { return nil }
                return CollaborationTerminalSelectionRectWire(
                    x: hasValidClip ? Double(clipped.minX / bounds.width) : 0,
                    y: hasValidClip ? Double(clipped.minY / bounds.height) : 0,
                    width: hasValidClip ? Double(clipped.width / bounds.width) : 0,
                    height: hasValidClip ? Double(clipped.height / bounds.height) : 0,
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
            color: peerIdentity.color,
            imageURL: nil
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
        terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
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
        trackCollaboration(
            .shareStopped,
            shareKind: .document,
            entrypoint: .documentHeaderButton,
            result: .completed
        )
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
        // Establish a single, unconditional observation dependency so every
        // connected surface's header re-renders on any membership change. Raw
        // @Observable dictionary tracking is unreliable here: two back-to-back
        // mutations (connect source, then target) across await hops can leave
        // one surface's header subscribed to a stale read, so only one pill
        // appears. Mirrors the workspaceParticipantSnapshotRevision pattern.
        _ = agentRoomHeaderRevision
        if let roomID = agentRoomIDsBySurfaceID[panel.id] {
            return AgentRoomHeaderState(
                isConnected: true,
                label: String(format: CollaborationStrings.agentRoomConnectedFormat, roomID.prefix(6).description)
            )
        }
        return AgentRoomHeaderState(isConnected: false, label: CollaborationStrings.connectClaudeRoom)
    }

    func beginAgentRoomWireDrag(
        sourcePanel: TerminalPanel,
        sourceScreenPoint: NSPoint? = nil,
        sourceWindow: NSWindow? = nil
    ) {
        draggingAgentRoomSourceSurfaceID = sourcePanel.id
        // Prefer the anchor computed by the drag source at mouse-drag time: the
        // cached anchor's screen point is only refreshed on layout, so it goes
        // stale when the window moves without relayout.
        if let sourceScreenPoint, let sourceWindow {
            agentRoomWireOverlay.start(from: sourceScreenPoint, in: sourceWindow)
        } else if let anchor = agentRoomWireAnchorsBySurfaceID[sourcePanel.id], anchor.window != nil {
            agentRoomWireOverlay.start(from: anchor.screenPoint, in: anchor.window)
        } else {
            agentRoomWireOverlay.start(from: NSEvent.mouseLocation, in: sourcePanel.surface.uiWindow)
        }
    }

    func endAgentRoomWireDrag() {
        draggingAgentRoomSourceSurfaceID = nil
        agentRoomWireOverlay.stop()
    }

    func updateAgentRoomWireAnchor(surfaceID: UUID, screenPoint: NSPoint, window: NSWindow?, ownerID: ObjectIdentifier) {
        guard let window else {
            removeAgentRoomWireAnchor(surfaceID: surfaceID, ownerID: ownerID)
            return
        }
        agentRoomWireAnchorsBySurfaceID[surfaceID] = AgentRoomWireAnchor(
            screenPoint: screenPoint,
            window: window,
            ownerID: ownerID
        )
    }

    func removeAgentRoomWireAnchor(surfaceID: UUID, ownerID: ObjectIdentifier) {
        // Owner-guarded so a deallocating stale anchor view (SwiftUI recreates them
        // during pane churn) cannot clobber the anchor a newer view just registered.
        guard agentRoomWireAnchorsBySurfaceID[surfaceID]?.ownerID == ownerID else { return }
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

    /// Fallback for wire drags that no drop target accepted (empty drag
    /// operation): when the release point sits on another surface's link
    /// button anchor, connect the two surfaces anyway so the gesture never
    /// silently drops the link.
    func connectAgentRoomWireToLinkButton(near screenPoint: NSPoint, sourceSurfaceID: UUID) {
        let hitRadius: CGFloat = 22
        let candidate = agentRoomWireAnchorsBySurfaceID
            .filter { $0.key != sourceSurfaceID && $0.value.window != nil }
            .map { (surfaceID: $0.key, distance: hypot($0.value.screenPoint.x - screenPoint.x, $0.value.screenPoint.y - screenPoint.y)) }
            .min { $0.distance < $1.distance }
        guard let candidate, candidate.distance <= hitRadius else { return }
        connectAgentRoomWire(
            sourceSurfaceID: sourceSurfaceID.uuidString,
            targetSurfaceID: candidate.surfaceID
        )
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

    private func trackCollaboration(
        _ event: CollaborationAnalyticsEvent,
        shareKind: CollaborationAnalyticsShareKind? = nil,
        entrypoint: CollaborationAnalyticsEntrypoint,
        result: CollaborationAnalyticsResult,
        properties: [String: Any] = [:],
        flush: Bool = false
    ) {
        var eventProperties = collaborationAnalyticsProperties()
        eventProperties.merge(properties) { _, new in new }
        productAnalytics.trackCollaboration(
            event,
            shareKind: shareKind,
            entrypoint: entrypoint,
            result: result,
            properties: eventProperties,
            flush: flush
        )
    }

    private func collaborationAnalyticsProperties() -> [String: Any] {
        [
            "peer_count": activeConnection?.peersByID.count ?? 0,
            "shared_documents_count": statesByDocumentID.values.filter(\.isShared).count,
            "shared_terminals_count": terminalStatesByID.values.filter(\.isShared).count,
            "session_count": connectionsBySessionCode.count,
            "relay_url_is_custom": relayURLString != Self.defaultRelayURLString,
        ]
    }

    private func trackCollaborationSessionStarted(sessionCode: String) {
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        if sessionStartedAtBySessionCode[normalizedCode] == nil {
            sessionStartedAtBySessionCode[normalizedCode] = ProcessInfo.processInfo.systemUptime
        }
    }

    private func trackCollaborationSessionEnded(sessionCode: String, reason: String) {
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return }
        let startedAt = sessionStartedAtBySessionCode.removeValue(forKey: normalizedCode)
        let duration = startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) }
        var properties = collaborationAnalyticsProperties()
        properties["collaboration_session_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(normalizedCode)
        properties["end_reason"] = reason
        if let duration {
            properties["duration_seconds"] = duration
        }
        trackCollaboration(
            .sessionDurationRecorded,
            entrypoint: .system,
            result: .completed,
            properties: properties,
            flush: true
        )
    }

    private func trackCollaborationLayoutSnapshot(
        reason: String,
        sessionCode explicitSessionCode: String? = nil,
        workspaceID explicitWorkspaceID: UUID? = nil,
        event: CollaborationAnalyticsEvent = .layoutSnapshotRecorded
    ) {
        let effectiveSessionCode = explicitSessionCode ?? sessionCode
        var properties = collaborationAnalyticsProperties()
        properties["snapshot_reason"] = reason
        if let effectiveSessionCode {
            properties["collaboration_session_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(Self.normalizedSessionCode(from: effectiveSessionCode))
        }

        let hostedSurfaceIDs = Set(hostedTerminalIDsBySurfaceID.keys)
        let mirroredSurfaceIDs = Set(mirroredTerminalIDsBySurfaceID.keys)
        let workspace = explicitWorkspaceID
            .flatMap { workspaceID in
                TerminalController.shared.tabManager?.tabs.first(where: { $0.id == workspaceID })
            }
            ?? TerminalController.shared.tabManager?.selectedWorkspace
            ?? TerminalController.shared.tabManager?.tabs.first

        if let workspace {
            properties.merge(workspace.cmuxAnalyticsLayoutProperties(snapshotReason: reason)) { _, new in new }
            let sharedPaneCount = workspace.bonsplitController.allPaneIds.filter { paneId in
                workspace.bonsplitController.tabs(inPane: paneId).contains { tab in
                    guard let panelId = workspace.panelIdFromSurfaceId(tab.id) else { return false }
                    return hostedSurfaceIDs.contains(panelId) || mirroredSurfaceIDs.contains(panelId)
                }
            }.count
            let remotePaneCount = workspace.bonsplitController.allPaneIds.filter { paneId in
                workspace.bonsplitController.tabs(inPane: paneId).contains { tab in
                    guard let panelId = workspace.panelIdFromSurfaceId(tab.id) else { return false }
                    return mirroredSurfaceIDs.contains(panelId)
                }
            }.count
            properties["workspace_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(workspace.id.uuidString)
            properties["shared_pane_count"] = sharedPaneCount
            properties["remote_pane_count"] = remotePaneCount
            properties["local_pane_count"] = max(0, (properties["pane_count"] as? Int ?? 0) - remotePaneCount)
        }

        trackCollaboration(
            event,
            entrypoint: .system,
            result: .completed,
            properties: properties
        )
    }

    private func trackCollaborationError(
        errorKind: String,
        operation: String,
        error: any Error
    ) {
        PostHogAnalytics.shared.trackError(
            errorKind: errorKind,
            severity: .warning,
            source: "CollaborationRuntime",
            properties: [
                "operation": operation,
                "error_name": String(describing: type(of: error)),
            ]
        )
    }

    private static func analyticsErrorDescription(_ error: any Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return String(describing: type(of: error))
        }
        let withoutHome = NSHomeDirectory().isEmpty
            ? description
            : description.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return String(withoutHome.prefix(160))
    }

    private static func analyticsRelayHost(from relayURLString: String) -> String {
        guard let host = URL(string: relayURLString)?.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return "unknown"
        }
        return host
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
        if let previousRoomID = agentRoomIDsBySurfaceID[surfaceID], previousRoomID != roomID {
            // Moving to a different room must drop the old membership, or the
            // store keeps routing digests/events to a surface that left.
            if let previousRoom = await agentRoomStore.disconnect(
                roomID: previousRoomID,
                memberID: agentRoomMemberIDsBySurfaceID[surfaceID],
                surfaceID: surfaceID.uuidString
            ) {
                cacheAgentRoom(previousRoom)
                try? await send(.agentRoomSnapshot(previousRoom))
            }
        }
        agentRoomIDsBySurfaceID[surfaceID] = roomID
        agentRoomMemberIDsBySurfaceID[surfaceID] = member.id
        let room = await agentRoomStore.connect(member: member, to: roomID)
        latestAgentRoomID = roomID
        cacheAgentRoom(room)
        reconcileAgentRoomMembership(with: room)
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
        let parsedSurfaceID = surfaceID.flatMap(UUID.init(uuidString:))
        // The surface's own room wins over latestAgentRoomID: another surface
        // may have created a newer room since this one connected.
        let targetRoomID = roomID
            ?? parsedSurfaceID.flatMap { agentRoomIDsBySurfaceID[$0] }
            ?? latestAgentRoomID
        guard let targetRoomID else { return ["disconnected": false, "error": "No Claude room is active."] }
        let memberID = parsedSurfaceID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        let room = await agentRoomStore.disconnect(
            roomID: targetRoomID,
            memberID: memberID,
            surfaceID: surfaceID
        )
        if let parsedSurfaceID {
            agentRoomIDsBySurfaceID.removeValue(forKey: parsedSurfaceID)
            agentRoomMemberIDsBySurfaceID.removeValue(forKey: parsedSurfaceID)
            agentRoomHeaderRevision &+= 1
        }
        if let room {
            cacheAgentRoom(room)
            reconcileAgentRoomMembership(with: room)
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
        let dispatch = dispatchAgentRoomEventIfNeeded(result.event)
        return [
            "posted": true,
            "event": encodedJSONObject(result.event),
            "room": agentRoomPayload(result.room),
            "dispatch": dispatch,
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
                _ = dispatchAgentRoomEventIfNeeded(event)
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
            "current_surface_id": surfaceID ?? NSNull(),
            "reachable_surfaces": room.members
                .filter { member in
                    guard let surfaceID else { return true }
                    return member.surfaceID != surfaceID
                }
                .map { member in
                    [
                        "member_id": member.id,
                        "surface_id": member.surfaceID,
                        "display_name": member.displayName ?? NSNull(),
                        "agent_session_id": member.agentSessionID ?? NSNull(),
                    ] as [String: Any]
                },
        ]
    }

    func agentRoomDigestForAutomationRequest(roomID: String?, surfaceID: String? = nil, since: Int?) -> [String: Any] {
        Task { @MainActor in
            _ = await agentRoomDigestForAutomation(roomID: roomID, surfaceID: surfaceID, since: since)
        }
        return ["requested": true]
    }

    func createSessionForAutomation(
        relayURL: String?,
        workspaceID: String? = nil,
        surfaceID: String? = nil
    ) async -> [String: Any] {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        do {
            let response = try await createSession()
            let connection = await connect(sessionID: response.sessionID, code: response.sessionCode)
            var didShareTerminal = false
            if let connection,
               let terminal = terminalForAutomation(workspaceID: workspaceID, surfaceID: surfaceID) {
                share(terminal: terminal, via: connection, entrypoint: .socketSession)
                didShareTerminal = true
            }
            trackCollaboration(
                .sessionCreated,
                entrypoint: .socketSession,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaboration(
                .inviteCodeCreated,
                entrypoint: .socketSession,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaborationLayoutSnapshot(reason: "session_created", sessionCode: response.sessionCode)
            var payload = statusPayload()
            payload["session_code"] = response.sessionCode
            payload["shared_terminal"] = didShareTerminal
            return payload
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
            trackCollaboration(
                .sessionCreated,
                entrypoint: .socketSession,
                result: .failed,
                properties: ["error_kind": "collaboration.session_create_failed"]
            )
            trackCollaborationError(
                errorKind: "collaboration.session_create_failed",
                operation: "createSessionForAutomation",
                error: error
            )
            return [
                "connected": false,
                "status": connectionLabel,
                "error": error.localizedDescription,
            ]
        }
    }

    func createSessionForAutomationRequest(
        relayURL: String?,
        workspaceID: String? = nil,
        surfaceID: String? = nil
    ) -> [String: Any] {
        Task { @MainActor in
            _ = await createSessionForAutomation(
                relayURL: relayURL,
                workspaceID: workspaceID,
                surfaceID: surfaceID
            )
        }
        return [
            "requested": true,
            "status": CollaborationStrings.connecting,
        ]
    }

    private func terminalForAutomation(workspaceID rawWorkspaceID: String?, surfaceID rawSurfaceID: String?) -> TerminalPanel? {
        guard let rawSurfaceID,
              let surfaceID = UUID(uuidString: rawSurfaceID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let workspaceID = rawWorkspaceID
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(UUID.init(uuidString:))
        guard let location = AppDelegate.shared?.workspaceContainingPanel(
            panelId: surfaceID,
            preferredWorkspaceId: workspaceID
        ) else {
            return nil
        }
        return location.workspace.panels[surfaceID] as? TerminalPanel
    }

    func joinSessionForAutomation(relayURL: String?, code: String) async -> [String: Any] {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        await joinSession(code: code, entrypoint: .socketSession)
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
        configureOrShare(terminal: terminal, entrypoint: .socketShareSelected)
        return statusPayload()
    }

    func leaveSessionForAutomation() -> [String: Any] {
        disconnectAllConnections()
        sessionCode = nil
        restoreAllTerminalTabPresentations()
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
        trackCollaboration(
            .shareStopped,
            entrypoint: .socketSession,
            result: .completed
        )
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
        let response = runCollaborationStartChooser()
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
        guard let code = runJoinCodeDialog() else { return }
        Task { await joinSession(code: code, entrypoint: .startDialogJoin) }
    }

    private func presentStartDialog(thenShare panel: any CollaborationEditablePanel) {
        let response = runCollaborationStartChooser()
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
        let response = runCollaborationStartChooser()
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
        guard let code = runJoinCodeDialog() else { return }
        Task {
            await joinSession(code: code, entrypoint: .startDialogJoin)
            share(panel: panel, entrypoint: .startDialogJoin)
        }
    }

    private func presentJoinDialog(thenBindWorkspaceFor terminal: TerminalPanel) {
        guard let code = runJoinCodeDialog() else { return }
        Task {
            if let connection = await joinSession(code: code, entrypoint: .startDialogJoin) {
                recordWorkspaceSession(connection.sessionCode, workspaceID: terminal.workspaceId)
            }
        }
    }

    private func runJoinCodeDialog() -> String? {
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.joinSession
        alert.informativeText = CollaborationStrings.joinMessage
        let joinButton = alert.addButton(withTitle: CollaborationStrings.joinSession)
        styleAccentAlertButtonTitleBlack(joinButton)
        alert.addButton(withTitle: CollaborationStrings.cancel)
        let joinButton = alert.buttons[0]

        let entryView = CollaborationInviteCodeEntryView(
            accessibilityLabel: CollaborationStrings.sessionCodePlaceholder
        )
        entryView.onSubmit = {
            guard entryView.isComplete else { return }
            joinButton.performClick(nil)
        }
        alert.accessoryView = entryView
        entryView.focusForTextEntry()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard entryView.isComplete else { return nil }
        let code = Self.normalizedSessionCode(from: entryView.code)
        return code.isEmpty ? nil : code
    }

    private func configureCollaborationAlertChrome(_ alert: NSAlert) {
        alert.icon = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
    }

    /// Forces an alert button's title to render in bold black. The default alert button
    /// takes the yellow accent color as its background, and the system-drawn white
    /// title is illegible on yellow — matching the black-on-yellow `.mosaicAccent`
    /// SwiftUI buttons keeps the two surfaces consistent.
    private func styleAccentAlertButtonTitleBlack(_ button: NSButton) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let pointSize = button.font?.pointSize ?? NSFont.systemFontSize
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
                .font: NSFont.systemFont(ofSize: pointSize, weight: .bold),
            ]
        )
    }

    private func runCollaborationStartChooser() -> NSApplication.ModalResponse {
        let panel = CollaborationStartChooserPanel()
        return panel.run()
    }

    private func createSessionAndPresentCode(relayURL: String?) async {
        if let relayURL {
            relayURLString = Self.normalizedRelayURL(from: relayURL)
        }
        #if DEBUG
        print("[PostHog] firing: collaboration_session_create_started")
        #endif
        PostHogAnalytics.shared.capture("collaboration_session_create_started")
        do {
            let response = try await createSession()
            #if DEBUG
            print("[PostHog] firing: collaboration_session_created")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_created")
            await connect(sessionID: response.sessionID, code: response.sessionCode)
            trackCollaboration(
                .sessionCreated,
                entrypoint: .startDialogCreate,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaboration(
                .inviteCodeCreated,
                entrypoint: .startDialogCreate,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaborationLayoutSnapshot(reason: "session_created", sessionCode: response.sessionCode)
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
            #if DEBUG
            print("[PostHog] firing: collaboration_session_create_failed")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_create_failed", properties: [
                "error": Self.analyticsErrorDescription(error),
            ])
            trackCollaboration(
                .sessionCreated,
                entrypoint: .startDialogCreate,
                result: .failed,
                properties: ["error_kind": "collaboration.session_create_failed"]
            )
            trackCollaborationError(
                errorKind: "collaboration.session_create_failed",
                operation: "createSessionAndPresentCode",
                error: error
            )
        }
    }

    private func createSessionAndShare(panel: any CollaborationEditablePanel) async {
        #if DEBUG
        print("[PostHog] firing: collaboration_session_create_started")
        #endif
        PostHogAnalytics.shared.capture("collaboration_session_create_started")
        do {
            let response = try await createSession()
            #if DEBUG
            print("[PostHog] firing: collaboration_session_created")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_created")
            await connect(sessionID: response.sessionID, code: response.sessionCode)
            trackCollaboration(
                .sessionCreated,
                shareKind: .document,
                entrypoint: .startDialogCreate,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaboration(
                .inviteCodeCreated,
                entrypoint: .startDialogCreate,
                result: .completed,
                properties: ["session_code_present": true]
            )
            trackCollaborationLayoutSnapshot(reason: "session_created", sessionCode: response.sessionCode)
            share(panel: panel, entrypoint: .startDialogCreate)
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
            #if DEBUG
            print("[PostHog] firing: collaboration_session_create_failed")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_create_failed", properties: [
                "error": Self.analyticsErrorDescription(error),
            ])
            trackCollaboration(
                .sessionCreated,
                shareKind: .document,
                entrypoint: .startDialogCreate,
                result: .failed,
                properties: ["error_kind": "collaboration.session_create_failed"]
            )
            trackCollaborationError(
                errorKind: "collaboration.session_create_failed",
                operation: "createSessionAndShareDocument",
                error: error
            )
        }
    }

    private func createSessionAndShare(terminal: TerminalPanel) async {
        #if DEBUG
        print("[PostHog] firing: collaboration_session_create_started")
        #endif
        PostHogAnalytics.shared.capture("collaboration_session_create_started")
        do {
            let response = try await createSession()
            #if DEBUG
            print("[PostHog] firing: collaboration_session_created")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_created")
            if let connection = await connect(sessionID: response.sessionID, code: response.sessionCode) {
                trackCollaboration(
                    .sessionCreated,
                    shareKind: .terminal,
                    entrypoint: .startDialogCreate,
                    result: .completed,
                    properties: ["session_code_present": true]
                )
                trackCollaboration(
                    .inviteCodeCreated,
                    entrypoint: .startDialogCreate,
                    result: .completed,
                    properties: ["session_code_present": true]
                )
                trackCollaborationLayoutSnapshot(reason: "session_created", sessionCode: response.sessionCode, workspaceID: terminal.workspaceId)
                recordWorkspaceSession(connection.sessionCode, workspaceID: terminal.workspaceId)
                share(terminal: terminal, via: connection, entrypoint: .startDialogCreate)
            }
            presentCreatedSessionDialog(code: response.sessionCode)
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionLabel = CollaborationStrings.connectionFailed
            #if DEBUG
            print("[PostHog] firing: collaboration_session_create_failed")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_create_failed", properties: [
                "error": Self.analyticsErrorDescription(error),
            ])
            trackCollaboration(
                .sessionCreated,
                shareKind: .terminal,
                entrypoint: .startDialogCreate,
                result: .failed,
                properties: ["error_kind": "collaboration.session_create_failed"]
            )
            trackCollaborationError(
                errorKind: "collaboration.session_create_failed",
                operation: "createSessionAndShareTerminal",
                error: error
            )
        }
    }

    private func presentCreatedSessionDialog(code: String) {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        let alert = NSAlert()
        configureCollaborationAlertChrome(alert)
        alert.messageText = CollaborationStrings.sessionCreatedTitle
        alert.informativeText = CollaborationStrings.sessionCreatedMessage(code: normalizedCode)
        let copyButton = alert.addButton(withTitle: CollaborationStrings.copyCode)
        styleAccentAlertButtonTitleBlack(copyButton)
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
        #if DEBUG
        print("[PostHog] firing: invite_code_copied")
        #endif
        PostHogAnalytics.shared.capture("invite_code_copied", properties: [
            "context": "session_created_dialog",
        ])
        trackCollaboration(
            .inviteCodeCopied,
            entrypoint: .createdSessionDialog,
            result: .completed,
            properties: ["session_code_present": true]
        )
        trackCollaborationLayoutSnapshot(reason: "invite_code_copied", sessionCode: normalizedCode)
    }

    @discardableResult
    private func joinSession(
        code: String,
        entrypoint: CollaborationAnalyticsEntrypoint
    ) async -> CollaborationRelayConnection? {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        #if DEBUG
        print("[PostHog] firing: collaboration_session_join_started")
        #endif
        PostHogAnalytics.shared.capture("collaboration_session_join_started")
        let connection = await connect(sessionID: normalizedCode, code: normalizedCode)
        if connection == nil {
            #if DEBUG
            print("[PostHog] firing: collaboration_session_join_failed")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_join_failed", properties: [
                "error": "collaboration.join_failed",
            ])
        } else {
            #if DEBUG
            print("[PostHog] firing: collaboration_session_joined")
            #endif
            PostHogAnalytics.shared.capture("collaboration_session_joined")
        }
        trackCollaboration(
            .sessionJoined,
            entrypoint: entrypoint,
            result: connection == nil ? .failed : .completed,
            properties: [
                "session_code_present": !normalizedCode.isEmpty,
                "error_kind": connection == nil ? "collaboration.join_failed" : "",
            ]
        )
        if connection == nil {
            trackCollaboration(
                .connectionFailed,
                entrypoint: entrypoint,
                result: .failed,
                properties: [
                    "operation": "join_session",
                    "error_kind": "collaboration.join_failed",
                ],
                flush: true
            )
        } else {
            trackCollaborationLayoutSnapshot(reason: "session_joined", sessionCode: normalizedCode)
        }
        return connection
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
        refreshPeerIdentityFromAuth()
        let normalizedCode = Self.normalizedSessionCode(from: code)
        if let existing = connectionsBySessionCode[normalizedCode] {
            sessionCode = normalizedCode
            connectionLabel = existing.connectionLabel
            reopenSharedDocumentsForCurrentSession()
            trackCollaborationSessionStarted(sessionCode: normalizedCode)
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
            trackCollaboration(
                .connectionFailed,
                entrypoint: .system,
                result: .failed,
                properties: [
                    "operation": "connect_url",
                    "error_kind": "collaboration.invalid_connect_url",
                ],
                flush: true
            )
            return nil
        }
        let task = URLSession.shared.webSocketTask(with: url)
        connection.webSocketTask = task
        task.resume()
        receiveNextMessage(for: connection)
        startHeartbeatLoop(for: connection)
        await nextSession.markConnected()
        trackCollaborationSessionStarted(sessionCode: normalizedCode)
        PostHogAnalytics.shared.capture("collaboration_ws_connected", properties: [
            "relay": Self.analyticsRelayHost(from: relayURLString),
        ])
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
        if let imageURL = peerIdentity.imageURL {
            components.queryItems?.append(URLQueryItem(name: "imageURL", value: imageURL))
        }
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

    private func share(
        panel: any CollaborationEditablePanel,
        entrypoint: CollaborationAnalyticsEntrypoint = .documentHeaderButton
    ) {
        guard let connection = activeConnection else {
            trackCollaboration(
                .documentShared,
                shareKind: .document,
                entrypoint: entrypoint,
                result: .failed,
                properties: ["error_kind": "collaboration.share_failed"]
            )
            return
        }
        let descriptor = descriptor(for: panel)
        let documentID = descriptor.documentID(sessionID: connection.sessionCode)
        panelsByDocumentID[documentID] = WeakCollaborationPanel(panel)
        descriptorsByDocumentID[documentID] = descriptor
        sessionCodesByDocumentID[documentID] = connection.sessionCode
        statesByDocumentID[documentID] = CollaborationDocumentHeaderState(
            isShared: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary,
            isConnectedToSession: true
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
                trackCollaboration(
                    .documentShared,
                    shareKind: .document,
                    entrypoint: entrypoint,
                    result: .completed,
                    properties: ["session_code_present": true]
                )
                trackCollaborationLayoutSnapshot(reason: "pane_shared", sessionCode: connection.sessionCode)
            } catch {
                lastErrorMessage = error.localizedDescription
                trackCollaboration(
                    .documentShared,
                    shareKind: .document,
                    entrypoint: entrypoint,
                    result: .failed,
                    properties: ["error_kind": "collaboration.share_failed"]
                )
                trackCollaborationError(
                    errorKind: "collaboration.share_failed",
                    operation: "shareDocument",
                    error: error
                )
            }
        }
    }

    private func share(terminal: TerminalPanel) {
        guard let connection = activeConnection else {
            trackCollaboration(
                .terminalShared,
                shareKind: .terminal,
                entrypoint: .terminalHeaderButton,
                result: .failed,
                properties: ["error_kind": "collaboration.share_failed"]
            )
            return
        }
        share(terminal: terminal, via: connection, entrypoint: .terminalHeaderButton)
    }

    private func share(
        terminal: TerminalPanel,
        via connection: CollaborationRelayConnection,
        entrypoint: CollaborationAnalyticsEntrypoint = .terminalHeaderButton
    ) {
        let descriptor = terminalDescriptor(for: terminal)
        let terminalID = descriptor.terminalID(sessionID: connection.sessionCode)
        // Deliberately no recordWorkspaceSession here: hosting is per-terminal.
        // Binding the session to the workspace made every sibling terminal's
        // header adopt the session (pill + share button) after sharing one
        // terminal. Workspace bindings are only recorded by the explicit
        // join-session flow.
        hostedTerminalsByID[terminalID] = WeakCollaborationTerminalPanel(terminal)
        hostedTerminalIDsBySurfaceID[terminal.id] = terminalID
        terminalOwnerParticipantIDsByID[terminalID] = peerIdentity.participantID
        terminalSessionRouter.record(terminalID: terminalID, sessionCode: connection.sessionCode)
        let ownerSnapshot = localParticipantSnapshot()
        terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
            isShared: true,
            isHosted: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary,
            ownerSnapshot: ownerSnapshot
        )
        syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: ownerSnapshot)
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
                broadcastHostedTerminalDimensions(terminalID: terminalID, connection: connection, force: true)
                trackCollaboration(
                    .terminalShared,
                    shareKind: .terminal,
                    entrypoint: entrypoint,
                    result: .completed,
                    properties: ["session_code_present": true]
                )
                trackCollaborationLayoutSnapshot(reason: "pane_shared", sessionCode: connection.sessionCode, workspaceID: terminal.workspaceId)
            } catch {
                lastErrorMessage = error.localizedDescription
                trackCollaboration(
                    .terminalShared,
                    shareKind: .terminal,
                    entrypoint: entrypoint,
                    result: .failed,
                    properties: ["error_kind": "collaboration.share_failed"]
                )
                trackCollaborationError(
                    errorKind: "collaboration.share_failed",
                    operation: "shareTerminal",
                    error: error
                )
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
                peerSummary: connection.peerSummary,
                isConnectedToSession: true
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
        let ownerSnapshot = ownerSnapshot(forPeerID: ownerPeerID, in: connection)
        terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
            isShared: true,
            isMirrored: true,
            statusText: CollaborationStrings.shared,
            peerSummary: connection.peerSummary,
            ownerSnapshot: ownerSnapshot
        )
        syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: ownerSnapshot)
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
            // The full render-grid seed is a one-shot frame with no follow-up
            // traffic. `processRemoteOutput` only issues an async refresh, which
            // can sit on a blank first frame until unrelated output arrives, so
            // force a synchronous present here to paint the seed immediately
            // (mirrors the forced present in `handleRemoteTerminalInput`). No-ops
            // safely when the surface is not yet live/in a window.
            panel.surface.forceRefresh(reason: "collaboration.renderGridSeed")
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
                viewportRowFromBottom: pointer.viewportRowFromBottom,
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

    /// Broadcasts the host terminal's current column count so peers can lock
    /// their mirror grid width. Sends only when the count changed (or `force`).
    ///
    /// - Parameters:
    ///   - terminalID: The hosted terminal identifier.
    ///   - connection: The relay connection to send over.
    ///   - recipientParticipantIDs: Explicit recipients, or nil for the default set.
    ///   - force: When true, sends even if the grid size is unchanged.
    private func broadcastHostedTerminalDimensions(
        terminalID: String,
        connection: CollaborationRelayConnection,
        recipientParticipantIDs: [String]? = nil,
        force: Bool = false
    ) {
        guard let panel = hostedTerminalsByID[terminalID]?.panel,
              let cells = panel.surface.gridCells(), cells.columns > 0, cells.rows > 0 else { return }
        let grid = TerminalGridSize(columns: cells.columns, rows: cells.rows)
        if !force, hostedTerminalBroadcastGridByID[terminalID] == grid { return }
        hostedTerminalBroadcastGridByID[terminalID] = grid
        let recipients = recipientParticipantIDs ?? recipientParticipantIDsForSending(
            terminalID: terminalID,
            connection: connection
        )
        Task {
            try? await send(CollaborationTerminalDimensionsWire(
                type: "terminal.dimensions",
                terminalID: terminalID,
                columns: grid.columns,
                rows: grid.rows,
                recipientParticipantIDs: recipients
            ), via: connection)
        }
    }

    private func handleRemoteTerminalDimensions(terminalID: String, columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        // Only mirrors lock their grid to the host; the host is authoritative.
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        panel.surface.applyLockedMirrorGrid(columns: columns, rows: rows)
    }

    private func handleRemoteTerminalClose(terminalID: String) {
        syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: nil)
        mirroredTerminalsByID.removeValue(forKey: terminalID)
        hostedTerminalsByID.removeValue(forKey: terminalID)
        removeTerminalSurfaceMappings(for: terminalID)
        hostedTerminalOutputSequencesByID.removeValue(forKey: terminalID)
        hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        hostedTerminalBroadcastGridByID.removeValue(forKey: terminalID)
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
            trackCollaboration(
                .connectionFailed,
                entrypoint: .system,
                result: .failed,
                properties: [
                    "operation": "receive",
                    "error_kind": "collaboration.receive_failed",
                    "error_name": String(describing: type(of: error)),
                ],
                flush: true
            )
            trackCollaborationSessionEnded(sessionCode: sessionCode, reason: "receive_failed")
            PostHogAnalytics.shared.capture("collaboration_ws_disconnected", properties: [
                "reason": String(describing: type(of: error)),
            ])
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
            trackCollaborationLayoutSnapshot(reason: "participant_joined", sessionCode: connection.sessionCode)
        case "peer.joined":
            let peer = try decoder.decode(CollaborationPeerJoinedWire.self, from: data).peer
            if peer.peerID != peerIdentity.peerID {
                connection.peersByID[peer.peerID] = peer
                refreshPeerSummaries(for: connection)
                trackCollaboration(
                    .participantJoined,
                    entrypoint: .system,
                    result: .completed,
                    properties: [
                        "participant_id_hash": ProductAnalyticsPrivacy.hashIdentifier(peer.stableParticipantID),
                        "participant_count": connection.peersByID.count + 1,
                    ]
                )
                trackCollaborationLayoutSnapshot(reason: "participant_joined", sessionCode: connection.sessionCode)
                sendHostedTerminalSeedsForNewPeer(peer, via: connection)
            }
        case "peer.left":
            let left = try decoder.decode(CollaborationPeerLeftWire.self, from: data)
            connection.peersByID.removeValue(forKey: left.peerID)
            refreshPeerSummaries(for: connection)
            trackCollaboration(
                .participantLeft,
                entrypoint: .system,
                result: .completed,
                properties: [
                    "participant_id_hash": ProductAnalyticsPrivacy.hashIdentifier(left.peerID),
                    "participant_count": connection.peersByID.count + 1,
                ]
            )
            trackCollaborationLayoutSnapshot(reason: "participant_left", sessionCode: connection.sessionCode)
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
            trackCollaborationLayoutSnapshot(reason: "pane_shared", sessionCode: connection.sessionCode)
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
            trackCollaborationLayoutSnapshot(reason: "pane_unshared", sessionCode: connection.sessionCode)
        case "terminal.dimensions":
            let dimensions = try decoder.decode(CollaborationTerminalDimensionsWire.self, from: data)
            handleRemoteTerminalDimensions(
                terminalID: dimensions.terminalID,
                columns: dimensions.columns,
                rows: dimensions.rows
            )
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
        let frame = terminalRenderGridFrameWithResolvedDefaults(snapshot.frame)
        try await send(CollaborationTerminalRenderGridWire(
            type: "terminal.render_grid",
            terminalID: terminalID,
            frame: frame,
            recipientParticipantIDs: recipientParticipantIDs ?? recipientParticipantIDsForSending(
                terminalID: terminalID,
                connection: connection
            )
        ), via: connection)
    }

    private func terminalRenderGridFrameWithResolvedDefaults(
        _ frame: MobileTerminalRenderGridFrame
    ) -> MobileTerminalRenderGridFrame {
        guard frame.full else { return frame }
        var resolved = frame
        if resolved.terminalForeground == nil {
            resolved.terminalForeground = GhosttyApp.shared.defaultForegroundColor.hexString()
        }
        if resolved.terminalBackground == nil {
            resolved.terminalBackground = GhosttyApp.shared.defaultBackgroundColor.hexString()
        }
        if resolved.terminalCursorColor == nil {
            resolved.terminalCursorColor = GhosttyApp.shared.defaultCursorColor.hexString()
        }
        return resolved
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
                    fromPeerID: peerIdentity.peerID,
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
                fromPeerID: peerIdentity.peerID,
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
        case .terminalDimensions(let terminalID, let columns, let rows):
            try await send(CollaborationTerminalDimensionsWire(
                type: "terminal.dimensions",
                terminalID: terminalID,
                columns: columns,
                rows: rows,
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
        PostHogAnalytics.shared.capture("collaboration_ws_disconnected", properties: [
            "reason": "heartbeat_failed",
        ])
    }

    private func updateState(
        documentID: String,
        isShared: Bool,
        connection: CollaborationRelayConnection
    ) {
        statesByDocumentID[documentID] = CollaborationDocumentHeaderState(
            isShared: isShared,
            statusText: isShared ? CollaborationStrings.shared : connection.connectionLabel,
            peerSummary: connection.peerSummary,
            isConnectedToSession: true
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
            let existingState = terminalStatesByID[terminalID]
            terminalStatesByID[terminalID] = CollaborationTerminalHeaderState(
                isShared: existingState?.isShared ?? false,
                isHosted: existingState?.isHosted ?? false,
                isMirrored: existingState?.isMirrored ?? false,
                statusText: existingState?.isShared == true ? CollaborationStrings.shared : connection.connectionLabel,
                peerSummary: connection.peerSummary,
                ownerSnapshot: existingState?.ownerSnapshot,
                workspaceSessionCode: existingState?.workspaceSessionCode,
                isWorkspaceSessionConnected: existingState?.isWorkspaceSessionConnected ?? false
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

    /// Mirrors authoritative room membership into the per-surface maps that
    /// drive the header "Claude room" pill, so every locally connected surface
    /// shows the tag no matter which entrypoint (click, wire drag, header
    /// drop, CLI) mutated the room. Uses the shared pure reducer so the
    /// invariant is unit-tested in one place.
    private func reconcileAgentRoomMembership(with room: ClaudeRoomSnapshot) {
        let reconciled = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(
                roomIDsBySurfaceID: agentRoomIDsBySurfaceID,
                memberIDsBySurfaceID: agentRoomMemberIDsBySurfaceID
            ),
            with: room
        )
        agentRoomIDsBySurfaceID = reconciled.roomIDsBySurfaceID
        agentRoomMemberIDsBySurfaceID = reconciled.memberIDsBySurfaceID
        agentRoomHeaderRevision &+= 1
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

    private func dispatchAgentRoomEventIfNeeded(_ event: ClaudeRoomEvent) -> [String: Any] {
        guard let prompt = agentRoomActiveDispatchPromptBuilder.prompt(for: event) else {
            return ["attempted": false]
        }
        let targetSurfaceIDs = Array(Set(event.targetSurfaceIDs)).sorted()
        var sent: [[String: Any]] = []
        var failed: [[String: Any]] = []
        for rawSurfaceID in targetSurfaceIDs {
            guard let surfaceID = UUID(uuidString: rawSurfaceID) else {
                failed.append(["surface_id": rawSurfaceID, "reason": "invalid_surface_id"])
                continue
            }
            guard let panel = terminalPanel(surfaceID: surfaceID) else {
                failed.append(["surface_id": rawSurfaceID, "reason": "surface_not_found"])
                continue
            }
            switch panel.sendInputResult(prompt + "\r") {
            case .sent:
                panel.surface.forceRefresh(reason: "collaboration.agentRoomDispatch")
                sent.append(["surface_id": rawSurfaceID, "queued": false])
            case .queued:
                sent.append(["surface_id": rawSurfaceID, "queued": true])
            case .inputQueueFull:
                failed.append(["surface_id": rawSurfaceID, "reason": "input_queue_full"])
            case .surfaceUnavailable:
                failed.append(["surface_id": rawSurfaceID, "reason": "surface_unavailable"])
            case .processExited:
                failed.append(["surface_id": rawSurfaceID, "reason": "process_exited"])
            }
        }
        return [
            "attempted": true,
            "sent": sent,
            "failed": failed,
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
            trackCollaborationLayoutSnapshot(reason: "session_left", sessionCode: connection.sessionCode)
            trackCollaborationSessionEnded(sessionCode: connection.sessionCode, reason: "disconnect_all")
            trackCollaboration(
                .sessionLeft,
                entrypoint: .system,
                result: .completed,
                properties: [
                    "collaboration_session_id_hash": ProductAnalyticsPrivacy.hashIdentifier(connection.sessionCode),
                ],
                flush: true
            )
            PostHogAnalytics.shared.capture("collaboration_ws_disconnected", properties: [
                "reason": "disconnect_all",
            ])
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

    static var sharingToggle: String {
        String(localized: "collaboration.sharing.toggle", defaultValue: "Sharing")
    }

    static var sharingToggleHelp: String {
        String(
            localized: "collaboration.sharing.toggle.help",
            defaultValue: "Turn sharing on or off for this item."
        )
    }

    static var viewingRemoteTerminal: String {
        String(localized: "collaboration.terminal.viewingRemote", defaultValue: "Viewing")
    }

    static var stopViewingRemoteTerminal: String {
        String(localized: "collaboration.terminal.stopViewingRemote", defaultValue: "Stop Viewing Remote Terminal")
    }

    static var startSession: String {
        String(localized: "collaboration.action.startSession", defaultValue: "Start session")
    }

    static var endSession: String {
        String(localized: "collaboration.action.endSession", defaultValue: "End session")
    }

    static var sessionPopoverTitle: String {
        String(localized: "collaboration.session.popover.title", defaultValue: "Collaboration Session")
    }

    static var sessionNotJoined: String {
        String(localized: "collaboration.session.notJoined", defaultValue: "No collaboration session")
    }

    static var sessionJoined: String {
        String(localized: "collaboration.session.joined", defaultValue: "Joined collaboration session")
    }

    static var sessionConnected: String {
        String(localized: "collaboration.session.connected", defaultValue: "Connected collaboration session")
    }

    static var sessionNotJoinedDetail: String {
        String(
            localized: "collaboration.session.notJoined.detail",
            defaultValue: "Create or join a session first. The Sharing toggle controls whether this terminal is visible to that session."
        )
    }

    static var sessionJoinedDetail: String {
        String(
            localized: "collaboration.session.joined.detail",
            defaultValue: "This workspace remembers the session. Turn Sharing on to share this terminal."
        )
    }

    static func sessionConnectedDetail(peerSummary: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.session.connected.detail", defaultValue: "Connected with %@."),
            peerSummary
        )
    }

    static func sessionCodeLabel(code: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.session.code.label", defaultValue: "Session %@"),
            code
        )
    }

    static func sessionPillLabel(code: String, peerSummary: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.session.pill.label", defaultValue: "Session %@ · %@"),
            code,
            peerSummary
        )
    }

    static var sessionParticipantsTitle: String {
        String(localized: "collaboration.session.participants.title", defaultValue: "People in session")
    }

    static var joinDifferentSession: String {
        String(localized: "collaboration.action.joinDifferentSession", defaultValue: "Join Different Session")
    }

    static var leaveSession: String {
        String(localized: "collaboration.action.leaveSession", defaultValue: "Leave Session")
    }

    static var terminalRecipientsTitle: String {
        String(localized: "collaboration.terminal.recipients.title", defaultValue: "Sharing with")
    }

    static var terminalRecipientsShareTitle: String {
        String(localized: "collaboration.terminal.recipients.shareTitle", defaultValue: "Sharing terminal with")
    }

    static var terminalRecipientsEmpty: String {
        String(
            localized: "collaboration.terminal.recipients.empty",
            defaultValue: "No one's here yet. Invite people to share this terminal."
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
        String(localized: "collaboration.terminal.stopSharing", defaultValue: "Stop sharing")
    }

    static var sharingTerminal: String {
        String(localized: "collaboration.terminal.sharing", defaultValue: "Sharing")
    }

    static var sharedTerminalTitle: String {
        String(localized: "collaboration.terminal.sharedTitle", defaultValue: "Shared Terminal")
    }

    static func terminalOwnerTitle(displayName: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.terminal.ownerTitleFormat", defaultValue: "%@'s terminal"),
            displayName
        )
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

    static var signInRequiredTitle: String {
        String(localized: "collaboration.signInRequired.title", defaultValue: "Sign into Mosaic")
    }

    static var signIn: String {
        String(localized: "collaboration.action.signIn", defaultValue: "Sign In")
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

@MainActor
private final class CollaborationStartChooserPanel {
    private let window: NSWindow
    private var response: NSApplication.ModalResponse = .alertThirdButtonReturn
    private var actionBoxes: [ButtonActionBox] = []

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 328))
        contentView.wantsLayer = true

        window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel

        let background = NSVisualEffectView(frame: contentView.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 28
        background.layer?.masksToBounds = true
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 12
        textStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textStack)

        let titleField = NSTextField(labelWithString: CollaborationStrings.startTitle)
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor
        textStack.addArrangedSubview(titleField)

        let messageField = NSTextField(wrappingLabelWithString: CollaborationStrings.startMessage)
        messageField.font = .systemFont(ofSize: 16, weight: .regular)
        messageField.textColor = .labelColor
        messageField.maximumNumberOfLines = 0
        messageField.preferredMaxLayoutWidth = 340
        textStack.addArrangedSubview(messageField)

        let buttonStack = NSStackView()
        buttonStack.orientation = .vertical
        buttonStack.alignment = .centerX
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.setHuggingPriority(.required, for: .vertical)
        stack.addArrangedSubview(buttonStack)

        let createButton = makeButton(title: CollaborationStrings.createSession, keyEquivalent: "\r") { [weak self] in
            self?.finish(.alertFirstButtonReturn)
        }
        createButton.bezelColor = .controlAccentColor
        // The accent bezel is the yellow primary color; use black title text so it
        // stays legible (the default prominent-button title is white).
        let createButtonTitleStyle = NSMutableParagraphStyle()
        createButtonTitleStyle.alignment = .center
        createButton.attributedTitle = NSAttributedString(
            string: CollaborationStrings.createSession,
            attributes: [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .paragraphStyle: createButtonTitleStyle,
            ]
        )
        let joinButton = makeButton(title: CollaborationStrings.joinSession, keyEquivalent: "") { [weak self] in
            self?.finish(.alertSecondButtonReturn)
        }
        let cancelButton = makeButton(title: CollaborationStrings.cancel, keyEquivalent: "\u{1b}") { [weak self] in
            self?.finish(.alertThirdButtonReturn)
        }
        buttonStack.addArrangedSubview(createButton)
        buttonStack.addArrangedSubview(joinButton)
        buttonStack.addArrangedSubview(cancelButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            textStack.widthAnchor.constraint(equalToConstant: 340),
            titleField.widthAnchor.constraint(equalToConstant: 340),
            messageField.widthAnchor.constraint(equalToConstant: 340),

            buttonStack.widthAnchor.constraint(equalToConstant: 340),
            createButton.widthAnchor.constraint(equalToConstant: 340),
            joinButton.widthAnchor.constraint(equalToConstant: 340),
            cancelButton.widthAnchor.constraint(equalToConstant: 340),
            createButton.heightAnchor.constraint(equalToConstant: 44),
            joinButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func run() -> NSApplication.ModalResponse {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            window.orderOut(nil)
            return response
        }

        parent.beginSheet(window)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return response
    }

    private func makeButton(
        title: String,
        keyEquivalent: String,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 16, weight: .semibold)
        button.keyEquivalent = keyEquivalent
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionBox = ButtonActionBox(action)
        actionBoxes.append(actionBox)
        button.target = actionBox
        button.action = #selector(ButtonActionBox.invoke)
        return button
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        self.response = response
        NSApp.stopModal()
    }

    private final class ButtonActionBox: NSObject {
        private let action: () -> Void

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        @objc func invoke() {
            action()
        }
    }
}

struct CollaborationHeaderControls<PanelModel>: View where PanelModel: CollaborationEditablePanel {
    @State private var runtime = CollaborationRuntime.shared
    let panel: PanelModel

    var body: some View {
        let state = runtime.state(for: panel)
        HStack(spacing: 5) {
            if state.isShared {
                Text(state.peerSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(CollaborationStrings.sharingToggle)
                .cmuxFont(size: 10, weight: .semibold)
                .foregroundStyle(state.isShared ? Color.accentColor : Color.secondary)
            Toggle(isOn: Binding(
                get: {
                    runtime.state(for: panel).isShared
                },
                set: { isSharing in
                    runtime.setSharing(isSharing, for: panel)
                }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(state.isShared ? "\(state.statusText) - \(state.peerSummary)" : CollaborationStrings.sharingToggleHelp)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.primary.opacity(state.isShared ? 0.10 : 0.06))
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(state.isShared ? 0.16 : 0.10), lineWidth: 0.5)
        }
    }
}
