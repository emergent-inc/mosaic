import AppKit
import MosaicAgentChat
import MosaicMobileCore
import MosaicCollaboration
import MosaicFoundation
import Foundation
import ImageIO
import Observation
import SwiftUI

@MainActor
protocol CollaborationEditablePanel: AnyObject {
    var collaborationFileURL: URL { get }
    var collaborationFilePath: String { get }
    var collaborationText: String { get }

    func applyCollaborationText(_ text: String)
}

/// Encodes and writes high-throughput collaboration relay frames off the main
/// actor.
///
/// `CollaborationRuntime` is `@MainActor`, and the terminal render / keystroke
/// path shares that thread. Doing reflective `JSONEncoder` work (plus base64 for
/// terminal output) and awaiting the socket write on the main actor injected
/// latency into typing. This actor moves that work onto its own executor; the
/// main actor only hands over `Sendable` value frames. The actor serializes its
/// own calls, so concurrent `send` calls preserve the order in which they reach
/// the actor (terminal output additionally carries per-frame sequence numbers,
/// so it does not rely on strict socket ordering).
///
/// Note: the cursor pointer stream is deliberately NOT routed here -- it encodes
/// and sends inline on the main actor to keep its low-latency ordering exact.
actor CollaborationRelayCodec {
    private let encoder = JSONEncoder()

    func send<T: Encodable & Sendable>(_ frame: T, over task: URLSessionWebSocketTask) async throws {
        let data = try encoder.encode(frame)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func send(encoded data: Data, over task: URLSessionWebSocketTask) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
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

private struct CollaborationPeerUpdateWire: Codable {
    let type: String
    let peer: CollaborationPeerWire
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

/// A mirror-bound content frame held back until the mirror grid is locked to
/// the host's dimensions (terminal byte replay is width-sensitive, so content
/// must never be processed at the mirror's provisional width).
private enum PendingMirroredTerminalFrame {
    case renderGrid(MobileTerminalRenderGridFrame)
    case output(sequence: UInt64, data: Data, caretPeerID: String?, connection: CollaborationRelayConnection)
}

/// Viewer -> host request to (re)send the full render-grid seed for a shared
/// terminal. Sent when a mirror pane exists but no full seed has been applied
/// (the one-shot seed can be dropped by the relay's size cap, raced past the
/// pane registration, or never produced because the host surface wasn't live
/// at share time). The relay forwards unknown `terminal.*` types opaquely, so
/// this needs no worker change.
private struct CollaborationTerminalRenderGridRequestWire: Codable {
    let type: String
    let terminalID: String
    let fromPeerID: String?
    let recipientParticipantIDs: [String]?

    init(
        type: String,
        terminalID: String,
        fromPeerID: String? = nil,
        recipientParticipantIDs: [String]? = nil
    ) {
        self.type = type
        self.terminalID = terminalID
        self.fromPeerID = fromPeerID
        self.recipientParticipantIDs = recipientParticipantIDs
    }
}

enum CollaborationTerminalRenderGridSeedLimiter {
    /// The collaboration relay silently drops any websocket message over
    /// 1 MiB (`parseEnvelope` in workers/collaboration/src/protocol.ts), and
    /// Cloudflare enforces the same cap on Durable Object websockets. A full
    /// render-grid seed with deep scrollback can exceed that, in which case
    /// viewers get `terminal.open` (a black mirror pane) but never the screen
    /// snapshot — the pane stays blank until the host produces new output.
    /// Keep seeds comfortably under the cap; the relay measures UTF-16 code
    /// units while we count UTF-8 bytes, which is always >= and thus safe.
    static let maxWireBytes = 768 * 1024

    /// Returns the first encoded seed payload that fits under `limit`,
    /// regenerating with progressively less scrollback (halving down to a
    /// screen-only frame, which is always small enough in practice).
    static func firstPayloadUnderLimit(
        startingScrollbackLines: Int,
        limit: Int = maxWireBytes,
        payload: (Int) -> Data?
    ) -> Data? {
        var lines = max(0, startingScrollbackLines)
        while true {
            guard let data = payload(lines) else { return nil }
            if data.count <= limit || lines == 0 { return data }
            lines = lines > 1 ? lines / 2 : 0
        }
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
    let scrolledToBottom: Bool?
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

@MainActor
final class CollaborationJoinAcknowledgementGate {
    private var continuations: [CheckedContinuation<Bool, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private var result: Bool?

    var isResolved: Bool {
        result != nil
    }

    func wait(timeout: Duration) async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
            if timeoutTask == nil {
                // This is a real protocol deadline: the relay must send session.joined
                // promptly after accepting the WebSocket, or the join is treated as failed.
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.fail()
                }
            }
        }
    }

    func succeed() {
        complete(true)
    }

    func fail() {
        complete(false)
    }

    private func complete(_ value: Bool) {
        guard result == nil else { return }
        result = value
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: value)
        }
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
    /// Tail of the ordered frame-processing chain. Incoming frames are handled
    /// strictly in arrival order, but decoupled from the socket read so the
    /// next `receive` can be armed before (potentially heavy) processing runs.
    var frameProcessingTask: Task<Void, Never>?
    /// Number of frames enqueued into the ordered chain that have not finished
    /// processing yet. When this is zero the chain is idle, so a latency-
    /// critical `terminal.output` echo can be applied inline (skipping the
    /// per-frame main-actor task hop) without reordering ahead of earlier work.
    var pendingOrderedFrameCount = 0
    var peersByID: [String: CollaborationPeerWire] = [:]
    var connectionLabel = CollaborationStrings.connecting
    let joinAcknowledgement = CollaborationJoinAcknowledgementGate()

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
        joinAcknowledgement.fail()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        frameProcessingTask?.cancel()
        frameProcessingTask = nil
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
    /// True when any locally connected member of this room has no Claude hook
    /// session record (context will not sync for that member).
    var isDegraded = false
    /// 1-based room number among active rooms on this machine.
    var displayNumber: Int?
    /// Stable palette index for accent color and pane highlight.
    var paletteIndex: Int?
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

    func pngData(for participant: CollaborationParticipantAvatarSnapshot) -> Data? {
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
        guard let image = Self.decodeImage(from: imageData) else {
            NSLog("[Collaboration] owner avatar decode failed bytes=\(imageData.count)")
            return nil
        }
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

    /// Decodes raw image bytes the same way the sidebar's `AsyncImage` does.
    ///
    /// `NSImage(data:)` is tried first; if it cannot decode the payload (some
    /// macOS versions refuse certain WebP/AVIF variants that ImageIO can still
    /// read), fall back to a direct `CGImageSource` decode so the tab matches
    /// the sidebar avatar for every format Clerk might serve.
    private static func decodeImage(from data: Data) -> NSImage? {
        if let image = NSImage(data: data), image.isValid, !image.representations.isEmpty {
            return image
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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

extension CollaborationTerminalOwnerAvatarImageCache {
    /// The production cache used by the app: fetches over `URLSession` and logs
    /// each rejected/failed fetch so a stuck-on-initials tab is diagnosable.
    /// Failures are never cached, so a later retry can still render the photo —
    /// matching the self-retrying sidebar `AsyncImage`.
    static func liveTerminalOwnerCache() -> CollaborationTerminalOwnerAvatarImageCache {
        CollaborationTerminalOwnerAvatarImageCache(
            fetcher: { url in
                let (data, response) = try await URLSession.shared.data(from: url)
                return CollaborationTerminalOwnerAvatarFetchResponse(
                    data: data,
                    statusCode: (response as? HTTPURLResponse)?.statusCode
                )
            },
            onOutcome: { url, outcome in
                NSLog("[Collaboration] owner avatar rejected outcome=\(outcome) url=\(url.absoluteString)")
            },
            onError: { url, error in
                NSLog("[Collaboration] owner avatar fetch error=\(error.localizedDescription) url=\(url.absoluteString)")
            }
        )
    }
}

extension Notification.Name {
    static let collaborationIncomingInviteCountDidChange = Notification.Name(
        "collaborationIncomingInviteCountDidChange"
    )
    static let collaborationIncomingInviteAlertDidChange = Notification.Name(
        "collaborationIncomingInviteAlertDidChange"
    )
}

private struct DirectoryMemberCacheEntry {
    let members: [CollaborationDirectoryMember]
    let fetchedAt: Date
}

@MainActor
@Observable
final class CollaborationRuntime {
    static let shared = CollaborationRuntime()
    static let agentRoomWirePasteboardTypeIdentifier = "com.mosaic.agent-room-wire"
    private static let defaultRelayURLString = "https://mosaic-collaboration-worker.dorsa-rohani.workers.dev"
    private static let terminalInitialRenderGridScrollbackLines = 10_000
    private static let joinAcknowledgementTimeout: Duration = .seconds(5)
    private static let inviteCodeStore = CollaborationInviteCodeStore()
    private static let workspaceSessionStore = CollaborationWorkspaceSessionStore(
        inviteCodeStore: CollaborationRuntime.inviteCodeStore
    )
    private static let outgoingInviteStore = CollaborationOutgoingInviteStore()
    private static let terminalRecipientSelectionStore = CollaborationTerminalRecipientSelectionStore(
        inviteCodeStore: CollaborationRuntime.inviteCodeStore
    )
    private static let directoryMemberCacheTTL: TimeInterval = 5 * 60

    private(set) var relayURLString = CollaborationRuntime.defaultRelayURLString
    private(set) var sessionCode: String?
    private(set) var connectionLabel = CollaborationStrings.disconnected
    private(set) var lastErrorMessage: String?
    private(set) var workspaceParticipantSnapshotRevision = 0
    private(set) var agentRoomHeaderRevision = 0

    /// Resolved sharing entitlements for the caller's active org, computed
    /// authoritatively by www. Drives UI gating (directory sharing vs codes).
    /// Defaults to free/hobby (codes on, directory off).
    private(set) var collaborationEntitlements = CollaborationEntitlements.hobbyDefault
    /// Incoming shared-session invites delivered to this user's inbox (the
    /// team "no codes" directory-sharing surface).
    private(set) var incomingSharedSessions: [CollaborationIncomingSession] = []
    /// The most recent genuinely-new invite that should be auto-surfaced as an
    /// alert anchored to the session pill. Cleared once handled/dismissed.
    private(set) var incomingInviteAlert: CollaborationIncomingSession?
    /// Bumped whenever `incomingInviteAlert` is set to a new invite, so a view
    /// can trigger presentation via `.onChange` without re-alerting on refetch.
    private(set) var incomingInviteAlertToken = 0
    /// Session ids we have already surfaced, so a refetch of the same invite
    /// does not re-alert.
    @ObservationIgnored private var seenIncomingSessionIDs: Set<String> = []

    /// Short-lived www-issued join grants keyed by relay room. Attached to the
    /// relay connect URL so the relay admits the connection.
    @ObservationIgnored private var grantsByRoom: [String: String] = [:]
    /// Signed session descriptors keyed by relay room, used to invite a
    /// teammate (via the org directory) into an already-created session.
    @ObservationIgnored private var sessionDescriptorsByRoom: [String: String] = [:]
    /// Teammate user ids we've sent directory invites to, keyed by relay room, so
    /// ending the session can withdraw those invites from their inbox instead of
    /// leaving stale invites that keep resurfacing after the session ends.
    @ObservationIgnored private var invitedTeammateUserIDsByRoom: [String: Set<String>] = [:]
    @ObservationIgnored private var directoryMemberCacheByOrgID: [String: DirectoryMemberCacheEntry] = [:]
    @ObservationIgnored private var directoryMemberRefreshTasksByOrgID: [String: Task<[CollaborationDirectoryMember], Never>] = [:]
    /// The org whose entitlements are currently reflected in
    /// `collaborationEntitlements`, so an active-org observation can skip
    /// redundant refreshes when the resolved org id has not actually changed.
    @ObservationIgnored private var lastEntitlementsOrgID: String?
    @ObservationIgnored private var incomingSharedSessionsPollTask: Task<Void, Never>?
    /// Persistent relay WebSocket that pushes invite nudges for the signed-in
    /// user, plus the user id it is bound to (so we restart on user change).
    @ObservationIgnored private var inboxRealtimeTask: Task<Void, Never>?
    @ObservationIgnored private var inboxRealtimeUserID: String?

    private var peerIdentity: CollaborationPeerIdentity
    private let localAvatarSeed: String
    private let terminalOwnerAvatarRenderer = CollaborationTerminalOwnerAvatarRenderer()
    private let terminalOwnerProfileImageCache = CollaborationTerminalOwnerAvatarImageCache.liveTerminalOwnerCache()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Encodes + writes high-throughput outbound frames (terminal output) off
    /// the main actor so the render/keystroke path is never blocked by JSON +
    /// base64 encoding. Inbound frames decode synchronously on main (a tight
    /// receive loop with no per-frame actor round-trip), and the cursor sends
    /// inline on main, both to preserve the smooth low-latency pointer path.
    private let frameWriter = CollaborationRelayCodec()
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
    /// Owning peer id for each mirrored terminal, used to attribute the room
    /// member created when a viewer wires the remote terminal they are viewing.
    private var mirroredTerminalOwnerPeerIDsByID: [String: String] = [:]
    private var terminalOwnerAvatarRequestKeysByID: [String: String] = [:]
    private var mirroredTerminalRenderGridPatchSequencesByID: [String: UInt64] = [:]
    private var mirroredTerminalRenderGridSequencesByID: [String: UInt64] = [:]
    /// Render-grid frames that arrived before the mirror pane registered
    /// (the seed can race `terminal.open` handling); drained on open.
    private var pendingMirroredRenderGridFramesByID: [String: [MobileTerminalRenderGridFrame]] = [:]
    /// Caps the pre-open seed buffer so a terminal that never opens cannot
    /// accumulate frames without bound.
    private static let pendingMirroredRenderGridFrameLimit = 4
    /// Delayed watchdogs that re-request the full seed from the host when a
    /// mirror pane exists but no full render-grid seed has been applied.
    private var mirroredRenderGridSeedRequestTasksByID: [String: Task<Void, Never>] = [:]
    private static let mirroredRenderGridSeedRequestDelay: Duration = .seconds(2)
    private static let mirroredRenderGridSeedRequestAttempts = 2
    /// Terminal IDs whose mirror grid has been locked to the host's columns
    /// x rows (i.e. `terminal.dimensions` has been applied at least once).
    /// Seed and output replay is gated on this: terminal byte streams are
    /// width-sensitive (zsh's partial-line `%` mark emits `$COLUMNS - 1`
    /// spaces to force a wrap), so content processed at the mirror's pre-lock
    /// width wraps differently than on the host and the two screens' rows
    /// drift apart permanently.
    private var mirroredTerminalGridLockedIDs: Set<String> = []
    /// Seed/output frames buffered until the mirror grid lock arrives,
    /// applied in arrival order when it does.
    private var pendingMirroredFramesAwaitingLockByID: [String: [PendingMirroredTerminalFrame]] = [:]
    /// Fallback timers that open the gate anyway for hosts that never send
    /// `terminal.dimensions` (or send it late): a briefly-mislaid layout
    /// beats an indefinitely black pane.
    private var mirroredGridLockFlushTasksByID: [String: Task<Void, Never>] = [:]
    private static let mirroredGridLockFlushDelay: Duration = .milliseconds(1500)
    /// If the buffer grows past this many frames the gate opens immediately;
    /// dropping output bytes is never acceptable (it corrupts the stream).
    private static let pendingMirroredFramesAwaitingLockLimit = 256
    /// The last host grid each mirror locked to, so a mid-session host grid
    /// change (window resize, fullscreen TUI toggle) can be detected and the
    /// mirror resynced with a fresh full seed. Content already laid out for
    /// the old grid cannot be repaired by replaying bytes: mirrors suppress
    /// reflow on resize, so only a RIS-led full seed repaints correctly.
    private var mirroredTerminalLockedGridByID: [String: TerminalGridSize] = [:]
    /// Debounced viewer->host full-seed re-requests after a grid change, so
    /// a live host window drag (a stream of grid changes) asks once at the
    /// end instead of per intermediate size. This is the safety net; the
    /// host also proactively reseeds on its own grid change (with a shorter
    /// debounce), and the request is skipped when that seed lands first.
    private var mirroredReseedRequestTasksByID: [String: Task<Void, Never>] = [:]
    private static let mirroredReseedRequestDebounce: Duration = .milliseconds(1500)
    /// Debounced host-side full reseeds after the host's own grid changed.
    private var hostedTerminalReseedTasksByID: [String: Task<Void, Never>] = [:]
    private static let hostedTerminalReseedDebounce: Duration = .milliseconds(600)
    /// Floor between consecutive host reseeds so grid flapping can never
    /// stream large seed frames back-to-back (which floods the socket ahead
    /// of latency-sensitive input echo and causes repaint churn).
    private var hostedTerminalLastReseedAtByID: [String: TimeInterval] = [:]
    private static let hostedTerminalReseedMinInterval: TimeInterval = 3.0
    /// One-shot seed retransmit after share start; heals the initial seed
    /// failing to land visibly on any viewer build.
    private static let shareStartSeedRetransmitDelay: Duration = .seconds(1)
    /// Mirrors whose content was rendered before any real grid lock arrived
    /// (the gate's fallback opened). A late lock resyncs them with a reseed.
    private var mirroredContentAppliedUnlockedIDs: Set<String> = []
    /// Seed-lifecycle debug logging; enable with `MOSAIC_COLLAB_SEED_DEBUG=1`
    /// to correlate host seed production with viewer application/presentation
    /// when diagnosing a blank mirror.
    private static let seedDebugEnabled =
        ProcessInfo.processInfo.environment["MOSAIC_COLLAB_SEED_DEBUG"] == "1"

    static func seedLog(_ message: @autoclosure () -> String) {
        guard seedDebugEnabled else { return }
        NSLog("[COLLABSEED] %@", message())
    }

    /// Echo-timing debug logging; enable with `MOSAIC_COLLAB_ECHO_TIMING=1`
    /// to measure the shared-terminal echo path. On the host it records when a
    /// PTY output chunk is handed to the socket; on the viewer it records the
    /// apply path (inline fast-path vs ordered chain) and the inter-arrival
    /// delta between consecutive applies. Even spacing means network-cadence
    /// typing; tight clusters separated by gaps mean the "stall then burst"
    /// regression is still queuing echoes somewhere.
    private static let echoTimingEnabled =
        ProcessInfo.processInfo.environment["MOSAIC_COLLAB_ECHO_TIMING"] == "1"

    static func echoLog(_ message: @autoclosure () -> String) {
        guard echoTimingEnabled else { return }
        NSLog("[COLLABECHO] %@", message())
        #if DEBUG
        // Also mirror into the debug event log file: NSLog from app processes
        // does not reliably land in `log show`, and the file gives ms-precision
        // timestamps alongside the existing collab.terminal.input.* lines.
        mosaicDebugLog("COLLABECHO \(message())")
        #endif
    }

    /// Monotonic millisecond clock for echo timing. `systemUptime` is immune to
    /// wall-clock adjustments, so inter-arrival deltas stay accurate.
    static func echoTimestampMillis() -> String {
        String(format: "%.1f", ProcessInfo.processInfo.systemUptime * 1000.0)
    }

    /// Last `terminal.output` apply time per terminal (viewer side), used only
    /// to compute the inter-arrival delta in `echoLog`.
    private var echoLastApplyAtByID: [String: TimeInterval] = [:]
    private var mirroredTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var hostedTerminalInputReportPrefixesByID: [String: Data] = [:]
    private var terminalStatesByID: [String: CollaborationTerminalHeaderState] = [:]
    private var terminalSelectionLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    /// Last send timestamp per surface, used to throttle pointer frames to the
    /// mouse-event cadence. Fired fire-and-forget (concurrent), which keeps
    /// motion smooth: send-completion latency never gates the update rate.
    private var terminalPointerLastSentAtBySurfaceID: [UUID: TimeInterval] = [:]
    /// Minimum spacing between pointer sends. 60 Hz matches the mouse-event
    /// stream and was the smooth baseline before the coalescing regression.
    private static let terminalPointerMinSendInterval: TimeInterval = 1.0 / 60.0
    /// Last time we probed a hosted terminal's grid size to detect a resize.
    /// The probe (`gridCells()` -> `ghostty_surface_size`) piggybacks on output,
    /// but output fires per keystroke, so we throttle the probe to a human-scale
    /// cadence to keep the typing path off that C call on every chunk.
    private var hostedTerminalDimensionsProbedAtByID: [String: TimeInterval] = [:]
    private static let hostedTerminalDimensionsProbeInterval: TimeInterval = 0.25
    private var snapshotFallbackTasks: [String: Task<Void, Never>] = [:]
    private var sessionStartedAtBySessionCode: [String: TimeInterval] = [:]
    private var isPresentingStartDialog = false
    /// Rooms, members (cursors), events, and indexed transcript turns persist
    /// under `~/.mosaicterm` so shared context survives an app relaunch. The
    /// in-memory-only store previously erased every room ledger on restart,
    /// which silently disconnected wired agents from their shared history.
    private let agentRoomStore = ClaudeRoomStore(
        persistenceURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mosaicterm", isDirectory: true)
            .appendingPathComponent("agent-rooms.json", isDirectory: false)
    )
    private let agentRoomDigestBuilder = ClaudeRoomDigestBuilder()
    private var agentRoomIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomMemberIDsBySurfaceID: [UUID: String] = [:]
    private var agentRoomSnapshotsByID: [String: ClaudeRoomSnapshot] = [:]
    /// Session codes of the relay connections that carry a mirrored terminal
    /// wired into each room. A wired remote endpoint must be reached over the
    /// connection that hosts its mirror even before the host has joined (so its
    /// member peer is not yet a room member on our side); recorded here so
    /// `broadcastAgentRoomFrame` always fans room frames to the owning host.
    private var agentRoomWiredOwnerConnectionCodesByRoomID: [String: Set<String>] = [:]
    /// Locally connected room surfaces with no Claude hook session record on
    /// disk (dead link: hooks never registered, so the agent neither publishes
    /// nor receives). Cached off the view path; the header pill only reads it.
    private var agentRoomDegradedSurfaceIDs: Set<UUID> = []
    @ObservationIgnored private var agentRoomWireAnchorsBySurfaceID: [UUID: AgentRoomWireAnchor] = [:]
    @ObservationIgnored private let agentRoomWireOverlay = AgentRoomWireOverlayController()
    @ObservationIgnored private var draggingAgentRoomSourceSurfaceID: UUID?
    @ObservationIgnored private let productAnalytics = ProductAnalytics.shared
    private var latestAgentRoomID: String?
    private static let agentRoomDisplayOrderDefaultsKey = "collaboration.agentRoom.displayOrder"
    private let agentRoomActiveDispatchPromptBuilder = AgentRoomActiveDispatchPromptBuilder()
    private let agentRoomTranscriptHistoryLimit = 24
    private let agentRoomContextPackTranscriptLimit = 8
    private let agentRoomTranscriptTurnCharacterLimit = 1_200
    private let agentRoomBackfillTurnsPerMember = 6
    /// Wire-time/recap transcript backfill only shares turns newer than this
    /// window before the join. Claude session transcript files are long-lived
    /// and reused across many rooms and test runs, so an unbounded tail read
    /// would resurrect ancient conversations (e.g. a prior test's messages)
    /// into a freshly created room. The window is generous enough to capture
    /// legitimate pre-wire context (type in one agent, then wire a peer moments
    /// later) while excluding stale history.
    private let agentRoomBackfillFreshnessWindow: TimeInterval = 30 * 60
    @ObservationIgnored private var terminalSurfaceReadyObserver: NSObjectProtocol?

    private init() {
        let displayName = NSFullUserName().isEmpty ? Host.current().localizedName ?? "mosaic" : NSFullUserName()
        localAvatarSeed = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? displayName
        peerIdentity = CollaborationPeerIdentity.persistedParticipant(displayName: displayName)
        installTerminalSurfaceReadyObserver()
        Task { @MainActor [weak self] in
            await self?.restorePersistedAgentRooms()
        }
    }

    /// Rehydrates cached room snapshots from disk and rebinds only surfaces
    /// that still have a current Claude hook session record. Persisted ledgers
    /// are history/debug data until a live pane proves it still owns that
    /// surface; otherwise a new pair of panes can accidentally inherit stale
    /// test-room context after an app restart.
    private func restorePersistedAgentRooms() async {
        let rooms = await agentRoomStore.allRooms()
        guard !rooms.isEmpty else { return }
        for room in rooms {
            cacheAgentRoom(room)
            reconcileAgentRoomMembership(with: liveHookBackedRoom(from: room))
        }
        // Do not seed latestAgentRoomID from persisted history. It is only a
        // convenience for explicit surface-less CLI/debug workflows in this app
        // run; using an old room as the default for fresh panes replays stale
        // test messages into new wiring sessions.
    }

    private func liveHookBackedRoom(from room: ClaudeRoomSnapshot) -> ClaudeRoomSnapshot {
        var liveRoom = room
        liveRoom.members = room.members.filter { member in
            guard let surfaceID = UUID(uuidString: member.surfaceID),
                  terminalPanel(surfaceID: surfaceID) != nil,
                  let hook = Self.claudeHookSessionRef(surfaceID: member.surfaceID),
                  let agentSessionID = member.agentSessionID else {
                return false
            }
            return hook.sessionID == agentSessionID
        }
        return liveRoom
    }

    private func restorePersistedAgentRoomMembershipIfNeeded(surfaceID: UUID?) async {
        guard let surfaceID, agentRoomIDsBySurfaceID[surfaceID] == nil else { return }
        let surfaceIDString = surfaceID.uuidString
        let rooms = await agentRoomStore.allRooms()
        for room in rooms where room.members.contains(where: { $0.surfaceID == surfaceIDString }) {
            cacheAgentRoom(room)
            reconcileAgentRoomMembership(with: liveHookBackedRoom(from: room))
            if agentRoomIDsBySurfaceID[surfaceID] != nil {
                return
            }
        }
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
            Task { @MainActor in
                self?.presentMirroredTerminalIfReady(surfaceID: surfaceID)
                await self?.restorePersistedAgentRoomMembershipIfNeeded(surfaceID: surfaceID)
            }
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

    private func refreshTerminalOwnerSnapshots(
        for peer: CollaborationPeerWire,
        in connection: CollaborationRelayConnection
    ) {
        let ownerParticipantID = peer.stableParticipantID
        let snapshot = ownerSnapshot(forPeerID: peer.peerID, in: connection)
        for (terminalID, participantID) in terminalOwnerParticipantIDsByID where participantID == ownerParticipantID {
            guard terminalSessionRouter.sessionCode(forTerminalID: terminalID) == connection.sessionCode else { continue }
            if var state = terminalStatesByID[terminalID] {
                state.ownerSnapshot = snapshot
                terminalStatesByID[terminalID] = state
            }
            syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: snapshot)
        }
    }

    private static func normalizedProfileImageURL(from rawValue: String?) -> URL? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
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
        let avatarPlan = CollaborationTerminalOwnerAvatarPlan(ownerSnapshot: ownerSnapshot, title: title)
        let iconImageData = avatarPlan.fallbackSnapshot.flatMap { terminalOwnerAvatarRenderer.pngData(for: $0) }
        workspace.setCollaborationTerminalTabPresentation(
            panelId: panel.id,
            title: avatarPlan.title,
            iconImageData: iconImageData
        )
        guard let profileImageURL = avatarPlan.profileImageURL,
              let requestKey = avatarPlan.requestKey else {
            terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
            return
        }
        terminalOwnerAvatarRequestKeysByID[terminalID] = requestKey
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let imageData = await terminalOwnerProfileImageCache.imageData(for: profileImageURL) else { return }
            guard let profileIconData = terminalOwnerAvatarRenderer.profilePNGData(from: imageData) else { return }
            guard CollaborationTerminalOwnerAvatarPlan.shouldApplyProfileImage(
                requestKey: requestKey,
                currentRequestKey: terminalOwnerAvatarRequestKeysByID[terminalID]
            ) else { return }
            guard let panel = hostedTerminalsByID[terminalID]?.panel ?? mirroredTerminalsByID[terminalID]?.panel else {
                return
            }
            guard let workspace = TerminalController.shared.tabManager?.tabs.first(where: { $0.id == panel.workspaceId }) else {
                return
            }
            workspace.setCollaborationTerminalTabPresentation(
                panelId: panel.id,
                title: avatarPlan.title,
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

    private func terminalIDsForSessionCleanup(_ sessionCode: String) -> [String] {
        let normalizedCode = Self.normalizedSessionCode(from: sessionCode)
        guard !normalizedCode.isEmpty else { return [] }
        return CollaborationTerminalSessionCleanupPlan(
            sessionCode: normalizedCode,
            terminalSessionRouter: terminalSessionRouter,
            hostedTerminalIDs: Array(hostedTerminalsByID.keys),
            mirroredTerminalIDs: Array(mirroredTerminalsByID.keys)
        ).terminalIDs
    }

    private func clearTerminalTabPresentations(forSession sessionCode: String) {
        let terminalIDs = terminalIDsForSessionCleanup(sessionCode)
        for terminalID in terminalIDs {
            syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: nil)
            terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
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
            if let connection = activeConnection {
                Task { @MainActor in
                    await refreshPeerIdentityForCollaborationAdvertise()
                    guard activeConnection === connection else { return }
                    share(panel: panel, entrypoint: entrypoint)
                }
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
                workspaceHasSession: workspaceSessionCode != nil,
                directorySharingEnabled: collaborationEntitlements.directorySharing
            ) {
            case .presentSessionChooser, .createSessionAndShareDirectly, .shareInWorkspaceSession:
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
                    workspaceHasSession: workspaceSessionCode != nil,
                    directorySharingEnabled: collaborationEntitlements.directorySharing
                ) {
                case .presentSessionChooser:
                    scheduleStartDialog(thenShare: terminal)
                case .createSessionAndShareDirectly:
                    // Team/enterprise: no create-or-join chooser. The session
                    // is created silently and the teammate picker is the whole
                    // sharing surface (see createSessionAndShare(terminal:)).
                    Task { await createSessionAndShare(terminal: terminal) }
                case .shareInWorkspaceSession:
                    guard let workspaceSessionCode else {
                        scheduleStartDialog(thenShare: terminal)
                        return
                    }
                    if let connection = connectionsBySessionCode[workspaceSessionCode] {
                        sessionCode = workspaceSessionCode
                        connectionLabel = connection.connectionLabel
                        Task { @MainActor in
                            await refreshPeerIdentityForCollaborationAdvertise()
                            share(terminal: terminal, via: connection, entrypoint: entrypoint)
                        }
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
                workspaceHasSession: workspaceSessionCode != nil,
                directorySharingEnabled: collaborationEntitlements.directorySharing
            ) {
            case .stopSharingHostedTerminal, .stopViewingRemoteTerminal:
                leave(terminal: terminal)
            case .presentSessionChooser, .createSessionAndShareDirectly, .shareInWorkspaceSession, .presentParticipantPicker:
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

        let panel = CollaborationSignInRequiredPanel()
        guard panel.run() == .alertFirstButtonReturn else {
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
        Task { @MainActor [weak self] in
            await self?.refreshCollaborationEntitlements()
        }
        startIncomingSharedSessionsPolling()
        startInboxRealtimeSubscription()
    }

    /// Presents the org-directory teammate picker for the active session and,
    /// on selection, sends a directory invite (the teammate receives it in
    /// their incoming-sessions inbox). Team/enterprise only.
    ///
    /// Existing-session entry: share an already-live session with a teammate.
    /// Requires an active connection (the session pill and recipient popovers
    /// only surface this once a session exists).
    func presentTeammateDirectorySharePicker() {
        guard activeConnection != nil else {
            lastErrorMessage = CollaborationStrings.shareWithTeammateNoSession
            NSSound.beep()
            return
        }
        Task { @MainActor in
            await runTeammateDirectorySharePicker(pendingSession: nil)
        }
    }

    /// Create-path entry: the session created by `pendingSession` may still be
    /// creating/connecting. Presents the picker immediately from the warm
    /// directory cache; once the owner picks a teammate, waits for the session
    /// to be ready (showing a spinner only if it hasn't landed yet) before
    /// sending the invite. This keeps the NSAlert off the relay-connect
    /// critical path. `pendingSession` resolves to whether the concurrent
    /// create + connect established a live connection.
    func presentTeammateDirectorySharePicker(pendingSession: Task<Bool, Never>) {
        Task { @MainActor in
            await runTeammateDirectorySharePicker(pendingSession: pendingSession)
        }
    }

    /// Shared picker core. When `pendingSession` is non-nil the session is
    /// being created concurrently, so the invite waits on it after selection;
    /// when nil the caller already guaranteed a live `activeConnection`.
    @MainActor
    private func runTeammateDirectorySharePicker(pendingSession: Task<Bool, Never>?) async {
        let members = await loadDirectoryMembers()
        guard !members.isEmpty else {
            CollaborationMessagePanel(
                title: CollaborationStrings.shareWithTeammateTitle,
                message: CollaborationStrings.directoryEmpty,
                buttonTitle: CollaborationStrings.okButton
            ).run()
            return
        }
        let alert = NSAlert()
        alert.messageText = CollaborationStrings.shareWithTeammateTitle
        alert.informativeText = CollaborationStrings.shareWithTeammateMessage
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        for member in members {
            popup.addItem(withTitle: member.label)
            popup.lastItem?.representedObject = member.userId
        }
        alert.accessoryView = popup
        applyCollaborationRegularAlertButtonTitleStyle(
            alert.addButton(withTitle: CollaborationStrings.shareButton)
        )
        applyCollaborationRegularAlertButtonTitleStyle(
            alert.addButton(withTitle: CollaborationStrings.cancelButton)
        )
        guard alert.runModal() == .alertFirstButtonReturn,
              let userID = popup.selectedItem?.representedObject as? String else { return }
        // On the create path the session may still be connecting (though it has
        // usually finished during the picker's own modal run loop). Wait for it
        // before inviting; the progress panel only surfaces if the wait exceeds
        // a short grace period, so a ready session never flashes a dialog.
        if let pendingSession {
            let progress = CollaborationProgressPanel(title: CollaborationStrings.sharePreparing)
            progress.present()
            let ready = await pendingSession.value
            progress.dismiss()
            guard ready else {
                lastErrorMessage = CollaborationStrings.shareWithTeammateNoSession
                NSSound.beep()
                return
            }
        }
        let shared = await shareCurrentSessionWithTeammate(userID: userID)
        if !shared {
            NSSound.beep()
        }
    }

    /// Presents the incoming shared-session inbox and joins the selected
    /// session (fetches a grant, then connects to the relay room).
    func presentIncomingSessionsInbox() {
        Task { @MainActor in
            // Reconcile against the relay first so ended sessions are pruned and
            // the picker only offers joinable sessions.
            await reconcileIncomingSharedSessions()
            await presentIncomingSessionsInboxDialog()
        }
    }

    /// Renders the incoming-sessions picker for whatever is currently in
    /// `incomingSharedSessions` (callers refresh first). Extracted so the
    /// DEBUG preview can reuse the exact recipient-facing dialog.
    @MainActor
    private func presentIncomingSessionsInboxDialog() async {
        let invites = incomingSharedSessions
        guard !invites.isEmpty else {
            let info = NSAlert()
            info.messageText = CollaborationStrings.incomingSessionsTitle
            info.informativeText = CollaborationStrings.incomingSessionsEmpty
            applyCollaborationAccentAlertButtonTitleStyle(
                info.addButton(withTitle: CollaborationStrings.okButton)
            )
            info.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = CollaborationStrings.incomingSessionsTitle
        alert.informativeText = CollaborationStrings.incomingSessionsPrompt
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        // Build rows through the shared helper so invites that share an
        // owner+org title stay visible (NSPopUpButton.addItem(withTitle:) drops
        // duplicate-titled items). Menu items are appended directly for the same
        // reason, with the session token stored as representedObject.
        let inputs = invites.map { invite in
            CollaborationInboxPickerInput(
                session: invite.session,
                baseTitle: CollaborationStrings.incomingSessionSubtitle(
                    ownerName: invite.ownerName ?? invite.ownerUserId,
                    orgName: invite.orgName ?? ""
                ),
                detail: Self.relativeInviteTime(from: invite.createdAt)
            )
        }
        for row in CollaborationInboxPicker.rows(from: inputs) {
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            item.representedObject = row.session
            popup.menu?.addItem(item)
        }
        alert.accessoryView = popup
        applyCollaborationRegularAlertButtonTitleStyle(
            alert.addButton(withTitle: CollaborationStrings.incomingSessionJoin)
        )
        applyCollaborationRegularAlertButtonTitleStyle(
            alert.addButton(withTitle: CollaborationStrings.cancelButton)
        )
        guard alert.runModal() == .alertFirstButtonReturn,
              let sessionToken = popup.selectedItem?.representedObject as? String,
              let invite = invites.first(where: { $0.session == sessionToken }) else { return }
        let joined = await acceptIncomingSharedSession(invite)
        if !joined {
            NSSound.beep()
        }
    }

    /// Formats an invite's ISO-8601 `createdAt` as a localized relative time
    /// (for example "5 minutes ago"), used only to disambiguate picker rows that
    /// share an owner+org title. Returns `nil` when the timestamp can't be parsed.
    private static func relativeInviteTime(from createdAt: String) -> String? {
        guard let date = iso8601InviteFormatter.date(from: createdAt)
            ?? iso8601InviteFormatterWithFractionalSeconds.date(from: createdAt) else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let iso8601InviteFormatter = ISO8601DateFormatter()
    private static let iso8601InviteFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    #if DEBUG
    /// Injects a sample incoming invite and opens the inbox so the recipient
    /// experience can be previewed without signing in as a second teammate.
    /// The fake invite can't actually be joined (bogus descriptor); it exists
    /// only to show the "Incoming sessions" badge and picker dialog.
    func debugPreviewIncomingSession() {
        Task { @MainActor in
            let sample = CollaborationIncomingSession(
                session: "debug-preview-\(UUID().uuidString)",
                ownerUserId: "debug-owner",
                ownerName: "Alex Rivera",
                ownerImageURL: nil,
                orgId: resolvedCollaborationOrgID ?? "debug-org",
                orgName: "Acme Inc",
                relayURL: nil,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            incomingSharedSessions = [sample]
            await presentIncomingSessionsInboxDialog()
        }
    }
    #endif

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

    private func refreshPeerIdentityForCollaborationAdvertise() async {
        let previousIdentity = peerIdentity
        if AppDelegate.shared?.auth?.coordinator.isAuthenticated == true {
            try? await AppDelegate.shared?.auth?.coordinator.refreshCurrentUserIdentity()
        }
        let didChange = refreshPeerIdentityFromAuth()
        guard didChange || previousIdentity != peerIdentity else { return }
        let peer = localPeerWire()
        for connection in connectionsBySessionCode.values {
            try? await send(CollaborationPeerUpdateWire(type: "peer.update", peer: peer), via: connection)
        }
    }

    private func localPeerWire() -> CollaborationPeerWire {
        CollaborationPeerWire(
            peerID: peerIdentity.peerID,
            participantID: peerIdentity.participantID,
            displayName: peerIdentity.displayName,
            color: peerIdentity.color,
            imageURL: peerIdentity.imageURL
        )
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
        let terminalIDs = terminalIDsForSessionCleanup(normalizedCode)
        clearTerminalTabPresentations(forSession: normalizedCode)
        trackCollaborationLayoutSnapshot(reason: "session_left", sessionCode: normalizedCode, workspaceID: terminal.workspaceId)
        for terminalID in terminalIDs {
            leave(terminalID: terminalID)
        }
        clearTerminalTabPresentations(forSession: normalizedCode)
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
        withdrawTeammateInvites(forRoom: normalizedCode)
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
                // Grid lock before content: seed replay is width-sensitive.
                await sendHostedTerminalDimensionsNow(
                    terminalID: terminalID,
                    connection: connection,
                    recipientParticipantIDs: recipients,
                    force: true
                )
                try? await sendTerminalRenderGridSnapshotIfPossible(
                    terminalID: terminalID,
                    scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                    full: true,
                    requireLiveScrollbackBottom: false,
                    recipientParticipantIDs: recipients,
                    via: connection
                )
                // Granting drive consent activates any agent-room bridge a viewer
                // wired earlier while the terminal was still read-only.
                await completeHostAgentRoomJoinsForConsentedTerminal(
                    surfaceID: terminal.id,
                    terminalID: terminalID
                )
            }
        }
    }

    /// Runs host join-completion for every room the given hosted surface was wired
    /// into, after the host grants terminal-drive consent. Broadcasts once per room
    /// that changed so the wiring viewer's agent begins exchanging context.
    private func completeHostAgentRoomJoinsForConsentedTerminal(
        surfaceID: UUID,
        terminalID: String
    ) async {
        let surfaceIDString = surfaceID.uuidString
        let roomsWithMember = agentRoomSnapshotsByID.values.filter { room in
            room.members.contains { $0.surfaceID == surfaceIDString }
        }
        for room in roomsWithMember {
            guard let member = room.members.first(where: { $0.surfaceID == surfaceIDString }) else {
                continue
            }
            if await completeHostAgentRoomJoin(member: member, surfaceUUID: surfaceID, roomID: room.id) {
                if let enriched = await agentRoomStore.room(id: room.id) {
                    cacheAgentRoom(enriched)
                    agentRoomHeaderRevision &+= 1
                    try? await send(.agentRoomSnapshot(enriched))
                }
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
        pendingMirroredRenderGridFramesByID.removeValue(forKey: terminalID)
        echoLastApplyAtByID.removeValue(forKey: terminalID)
        mirroredRenderGridSeedRequestTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalGridLockedIDs.remove(terminalID)
        pendingMirroredFramesAwaitingLockByID.removeValue(forKey: terminalID)
        mirroredGridLockFlushTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalLockedGridByID.removeValue(forKey: terminalID)
        mirroredReseedRequestTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredContentAppliedUnlockedIDs.remove(terminalID)
        hostedTerminalReseedTasksByID.removeValue(forKey: terminalID)?.cancel()
        hostedTerminalLastReseedAtByID.removeValue(forKey: terminalID)
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
        // The byte-faithful raw stream is the mirror's sole live painter; it
        // reproduces scrollback, TUIs, and resizes exactly. We do NOT also send
        // a live render-grid delta here: the two transports interleave and
        // desync, which left stale rows on the peer. The render-grid path is
        // used only for the cold-attach full seed.
        //
        // Echo is latency-critical: this is the byte a viewer sees after typing
        // travels host<->relay<->viewer. Encode inline and hand the frame
        // straight to URLSession's FIFO send queue, exactly like keystroke
        // input and pointer frames. Routing through the `frameWriter` codec
        // actor (plus the extra `Task {}` hop) queued the echo behind large
        // in-flight frames (768KB render-grid seeds, output bursts), which the
        // viewer felt as typing lag. FIFO ordering is preserved because
        // `noteTerminalOutput` runs on the main actor and `task.send` enqueues
        // in call order.
        if let connection = connection(forTerminalID: terminalID),
           let task = connection.webSocketTask {
            let wire = CollaborationTerminalOutputWire(
                type: "terminal.output",
                terminalID: terminalID,
                sequence: sequence,
                dataBase64: data.base64EncodedString(),
                caretPeerID: terminalOutputPeerID(for: terminalID),
                recipientParticipantIDs: recipientParticipantIDsForSending(
                    terminalID: terminalID,
                    connection: connection
                )
            )
            if let payload = try? encoder.encode(wire) {
                task.send(.string(String(decoding: payload, as: UTF8.self))) { _ in }
                Self.echoLog(
                    "host-send terminal=\(terminalID.prefix(8)) bytes=\(data.count) " +
                    "t=\(Self.echoTimestampMillis())"
                )
            }
        }
        // A host resize produces redraw output; piggyback a column re-broadcast
        // so peers re-lock their mirror width when the host grid changes. Output
        // fires per keystroke, so throttle the grid probe to a human-scale
        // cadence -- a resize is a human action and 250ms detection latency is
        // imperceptible, but probing every chunk kept the typing path on a
        // per-keystroke `ghostty_surface_size` call.
        let now = ProcessInfo.processInfo.systemUptime
        let lastProbedAt = hostedTerminalDimensionsProbedAtByID[terminalID] ?? 0
        if now - lastProbedAt >= Self.hostedTerminalDimensionsProbeInterval {
            hostedTerminalDimensionsProbedAtByID[terminalID] = now
            if let connection = connection(forTerminalID: terminalID) {
                broadcastHostedTerminalDimensions(terminalID: terminalID, connection: connection)
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
        guard let connection = connection(forTerminalID: terminalID),
              let task = connection.webSocketTask else { return }
        let wire = CollaborationTerminalInputWire(
            type: "terminal.input",
            terminalID: terminalID,
            inputID: "\(peerIdentity.peerID)-\(UUID().uuidString)",
            dataBase64: filteredData.base64EncodedString(),
            fromPeerID: peerIdentity.peerID,
            recipientParticipantIDs: recipientParticipantIDsForSending(
                terminalID: terminalID,
                connection: connection
            )
        )
        // Keystrokes are latency-critical: encode inline (tiny payload) and
        // hand the frame straight to URLSession's FIFO send queue, exactly
        // like pointer frames. Routing through the `frameWriter` codec actor
        // queued keystrokes behind large frames (768KB render-grid seeds,
        // output bursts), which read as typing lag on the shared terminal.
        guard let payload = try? encoder.encode(wire) else { return }
        task.send(.string(String(decoding: payload, as: UTF8.self))) { _ in }
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
        scrolledToBottom: Bool,
        visible: Bool,
        coordinateSpace: String
    ) {
        let terminalID = hostedTerminalIDsBySurfaceID[surfaceID] ?? mirroredTerminalIDsBySurfaceID[surfaceID]
        guard let terminalID else { return }

        // Throttle to the mouse-event cadence and fire the send concurrently
        // (fire-and-forget). Updates ride the natural pointer-move stream, which
        // keeps spacing even and motion smooth. A timer-coalesced drain was
        // tried and reverted: `Task.sleep` jitter made the flush interval wobble
        // and the cursor advanced in irregular time steps (stuttery/jumpy).
        let now = ProcessInfo.processInfo.systemUptime
        if visible {
            let lastSentAt = terminalPointerLastSentAtBySurfaceID[surfaceID] ?? 0
            guard now - lastSentAt >= Self.terminalPointerMinSendInterval else { return }
            terminalPointerLastSentAtBySurfaceID[surfaceID] = now
        } else {
            terminalPointerLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
        }

        guard let connection = connection(forTerminalID: terminalID),
              let task = connection.webSocketTask else { return }
        let wire = CollaborationTerminalPointerWire(
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
            viewportRowFromBottom: viewportRowFromBottom,
            scrolledToBottom: scrolledToBottom
        )
        // Encode synchronously and hand the frame straight to URLSession's
        // FIFO send queue via the completion-handler API. Deliberately NOT
        // routed through `frameWriter` (its actor serialization can let rapid
        // fire-and-forget sends reach the socket out of creation order) and
        // NOT wrapped in a per-move `Task {}` (scheduling a fresh task on a
        // busy main actor added spacing jitter between consecutive pointer
        // frames, which read as stutter on the receiving side).
        guard let data = try? encoder.encode(wire) else { return }
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
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
        mirroredTerminalOwnerPeerIDsByID.removeValue(forKey: terminalID)
        terminalOwnerAvatarRequestKeysByID.removeValue(forKey: terminalID)
        for surfaceID in hostedSurfaceIDs + mirroredSurfaceIDs {
            terminalSelectionLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
            terminalPointerLastSentAtBySurfaceID.removeValue(forKey: surfaceID)
        }
        // A terminal leaving collaboration (mirror closed, host stopped sharing,
        // session left) must also drop any agent-room member bridged from it, so
        // the room no longer routes context to a surface that is gone.
        teardownBridgedAgentRoomMembership(forTerminalID: terminalID)
    }

    /// Removes the agent-room member that was bridged from a collaboration
    /// terminal (the host surface embedded in the terminal id) and broadcasts the
    /// updated room. Safe no-op when the terminal was never wired into a room.
    private func teardownBridgedAgentRoomMembership(forTerminalID terminalID: String) {
        guard let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID) else { return }
        let memberSurfaceID = parsed.surfaceID.uuidString
        let affectedRoomIDs = agentRoomSnapshotsByID.values
            .filter { room in room.members.contains { $0.surfaceID == memberSurfaceID } }
            .map(\.id)
        guard !affectedRoomIDs.isEmpty else { return }
        Task { @MainActor in
            for roomID in affectedRoomIDs {
                let memberID = agentRoomMemberID(surfaceID: memberSurfaceID, inRoomID: roomID)
                guard let room = await agentRoomStore.disconnect(
                    roomID: roomID,
                    memberID: memberID,
                    surfaceID: memberSurfaceID
                ) else { continue }
                cacheAgentRoom(room)
                reconcileAgentRoomMembership(with: room)
                agentRoomHeaderRevision &+= 1
                try? await send(.agentRoomSnapshot(room))
            }
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
        if let roomID = resolvedAgentRoomID(forPanel: panel) {
            let isDegraded: Bool
            if agentRoomIDsBySurfaceID[panel.id] != nil {
                // Degraded when ANY local member of this room has a dead hook link:
                // a silently unplugged peer breaks context sync for everyone, so
                // every pane in the room should surface it.
                isDegraded = agentRoomDegradedSurfaceIDs.contains { surfaceID in
                    agentRoomIDsBySurfaceID[surfaceID] == roomID
                }
            } else if let member = mirrorHostRoomMember(forPanel: panel, roomID: roomID) {
                // A mirrored pane is degraded until the host completes the join
                // (attaches its live Claude session), which only happens once the
                // host has granted the terminal-drive bridge consent.
                isDegraded = member.agentSessionID == nil
            } else {
                isDegraded = false
            }
            // Display numbers follow the persistent first-seen wiring order and
            // must stay stable when another room empties out. Filtering to only
            // currently-populated rooms here renumbers survivors: emptying the
            // room that happens to sit lower in the order would silently relabel
            // (and recolor) a still-populated room — e.g. wiring the last pane
            // out of "Room 1" made the remaining room jump from "Room 2" to
            // "Room 1". Gaps in numbering are intentional and preferred over
            // relabeling an existing room.
            let displayNumber = AgentRoomDisplayPalette.displayNumber(
                for: roomID,
                orderedRoomIDs: agentRoomDisplayOrder
            )
            return AgentRoomHeaderState(
                isConnected: true,
                label: CollaborationStrings.agentRoomLabel(number: displayNumber),
                isDegraded: isDegraded,
                displayNumber: displayNumber,
                paletteIndex: AgentRoomDisplayPalette.paletteIndex(forDisplayNumber: displayNumber)
            )
        }
        return AgentRoomHeaderState(isConnected: false, label: CollaborationStrings.connectAgentRoom)
    }

    /// The room a pane's header pill should reflect. Local panes read the direct
    /// membership map; a mirrored pane resolves through the host surface embedded
    /// in its collaboration terminal id, since the room member is keyed on the
    /// host surface (not the local mirror pane UUID).
    private func resolvedAgentRoomID(forPanel panel: TerminalPanel) -> String? {
        if let roomID = agentRoomIDsBySurfaceID[panel.id] { return roomID }
        if let terminalID = mirroredTerminalIDsBySurfaceID[panel.id],
           let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID) {
            return roomID(forMemberSurfaceID: parsed.surfaceID.uuidString)
        }
        return nil
    }

    private func mirrorHostRoomMember(forPanel panel: TerminalPanel, roomID: String) -> ClaudeRoomMember? {
        guard let terminalID = mirroredTerminalIDsBySurfaceID[panel.id],
              let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID) else {
            return nil
        }
        let memberSurfaceID = parsed.surfaceID.uuidString
        return agentRoomSnapshotsByID[roomID]?.members.first { $0.surfaceID == memberSurfaceID }
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
            // A mirrored (remote) pane registers the host's real surface into the
            // room, not its local mirror pane UUID, so it must go through the
            // endpoint path rather than the local surface-id automation helpers.
            if mirroredTerminalIDsBySurfaceID[panel.id] != nil {
                let endpoint = agentRoomWireEndpoint(localSurfaceID: panel.id)
                if let roomID = endpoint.existingRoomID {
                    await disconnectAgentRoomEndpoint(endpoint, roomID: roomID)
                } else if endpoint.isStaleMirror {
                    lastErrorMessage = Self.agentRoomStaleMirrorWireError
                } else {
                    let roomID = AgentRoomSelection.roomIDForSurfaceConnection(
                        requestedRoomID: nil,
                        surfaceWasExplicit: true,
                        mappedSurfaceRoomID: nil,
                        latestRoomID: latestAgentRoomID,
                        newRoomID: UUID().uuidString
                    )
                    _ = await connectAgentRoomEndpoint(endpoint, roomID: roomID)
                }
                return
            }
            if agentRoomIDsBySurfaceID[panel.id] != nil {
                _ = await disconnectAgentRoomSurfaceForAutomation(
                    roomID: nil,
                    surfaceID: panel.id.uuidString
                )
            } else {
                _ = await connectAgentRoomSurfaceForAutomation(
                    roomID: nil,
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
            // Resolve each wire end to a member endpoint. A mirrored pane resolves
            // to the host's real surface + owner peer (see `agentRoomWireEndpoint`),
            // so wiring the terminal you are viewing bridges the remote host agent
            // into the room rather than the agent-less local mirror pane.
            let sourceEndpoint = sourceUUID.map { agentRoomWireEndpoint(localSurfaceID: $0) }
            let targetEndpoint = agentRoomWireEndpoint(localSurfaceID: targetUUID)
            // Refuse to wire a stale mirror: it would register a ghost host
            // member that never joins and whose peer is unreachable, forking a
            // one-machine room instead of a shared one.
            if targetEndpoint.isStaleMirror || (sourceEndpoint?.isStaleMirror ?? false) {
                lastErrorMessage = Self.agentRoomStaleMirrorWireError
                return
            }
            let roomID = AgentRoomSelection.roomIDForWire(
                sourceRoomID: sourceEndpoint?.existingRoomID,
                targetRoomID: targetEndpoint.existingRoomID,
                newRoomID: UUID().uuidString
            )

            if let sourceEndpoint, sourceEndpoint.localSurfaceID != targetUUID {
                _ = await connectAgentRoomEndpoint(sourceEndpoint, roomID: roomID)
            }

            _ = await connectAgentRoomEndpoint(targetEndpoint, roomID: roomID)
        }
    }

    /// One end of an agent-room wire, resolved to the member identity that should
    /// be registered in the room.
    ///
    /// For a normal local terminal, the member surface id is the pane's own UUID.
    /// For a mirrored (remote) pane, it is the host's real surface UUID extracted
    /// from the mirror's collaboration terminal id, with `peerID` set to the
    /// owning peer; the host completes the join for that surface on its side.
    private struct AgentRoomWireEndpoint {
        let localSurfaceID: UUID
        let memberSurfaceID: String
        let peerID: String
        let isRemote: Bool
        let displayName: String?
        let existingRoomID: String?
        /// A mirrored endpoint whose owning share is no longer live (its owner
        /// peer is not connected on the mirror's session). Wiring it would
        /// register a ghost member the host can never join, so callers refuse.
        let isStaleMirror: Bool
        /// The relay session that carries the mirror, so room frames can be
        /// routed to the host even before it has joined the room.
        let owningConnectionSessionCode: String?
    }

    private func agentRoomWireEndpoint(localSurfaceID: UUID) -> AgentRoomWireEndpoint {
        if let terminalID = mirroredTerminalIDsBySurfaceID[localSurfaceID],
           let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID) {
            let memberSurfaceID = parsed.surfaceID.uuidString
            let owningConnection = connection(forTerminalID: terminalID)
            let ownerPeerID = mirroredTerminalOwnerPeerIDsByID[terminalID]
            // Live only when the owning peer is currently connected on the
            // mirror's session. A mirror pane left over from a previous session
            // (surface + peer ids regenerate on relaunch) resolves to a ghost.
            let isLive = ownerPeerID.map { owningConnection?.peersByID[$0] != nil } ?? false
            return AgentRoomWireEndpoint(
                localSurfaceID: localSurfaceID,
                memberSurfaceID: memberSurfaceID,
                peerID: ownerPeerID ?? peerIdentity.peerID,
                isRemote: true,
                displayName: mirroredTerminalsByID[terminalID]?.panel?.displayTitle,
                existingRoomID: roomID(forMemberSurfaceID: memberSurfaceID),
                isStaleMirror: !isLive,
                owningConnectionSessionCode: owningConnection?.sessionCode
            )
        }
        return AgentRoomWireEndpoint(
            localSurfaceID: localSurfaceID,
            memberSurfaceID: localSurfaceID.uuidString,
            peerID: peerIdentity.peerID,
            isRemote: false,
            displayName: terminalPanel(surfaceID: localSurfaceID)?.displayTitle,
            existingRoomID: agentRoomIDsBySurfaceID[localSurfaceID],
            isStaleMirror: false,
            owningConnectionSessionCode: nil
        )
    }

    /// User-facing error shown when a wire targets a mirrored terminal whose
    /// share is no longer live (e.g. a stale pane after the host relaunched).
    private static var agentRoomStaleMirrorWireError: String {
        String(
            localized: "collaboration.agentRoom.staleMirrorWire",
            defaultValue: "This shared terminal is no longer live. Re-open it, then wire the agents again."
        )
    }

    /// The room a member surface currently belongs to, looked up across cached
    /// room snapshots. Used for remote (mirrored) surfaces, whose host surface id
    /// is never present in the local `agentRoomIDsBySurfaceID` map.
    private func roomID(forMemberSurfaceID memberSurfaceID: String) -> String? {
        agentRoomSnapshotsByID.values.first { room in
            room.members.contains { $0.surfaceID == memberSurfaceID }
        }?.id
    }

    private func agentRoomMemberID(surfaceID memberSurfaceID: String, inRoomID roomID: String) -> String? {
        agentRoomSnapshotsByID[roomID]?.members.first { $0.surfaceID == memberSurfaceID }?.id
    }

    /// Connects one wire endpoint (local or remote) into a room, broadcasting the
    /// updated snapshot so other peers converge. A local endpoint attaches its own
    /// Claude hook session and backfills its transcript; a remote endpoint only
    /// registers the host surface member, and the host attaches its live session
    /// on its side via `applyRemoteAgentRoomMembership`.
    @discardableResult
    private func connectAgentRoomEndpoint(
        _ endpoint: AgentRoomWireEndpoint,
        roomID: String
    ) async -> ClaudeRoomSnapshot? {
        if await agentRoomStore.room(id: roomID) == nil {
            let created = await agentRoomStore.createRoom(id: roomID)
            cacheAgentRoom(created)
            registerAgentRoomDisplayOrder(roomID: roomID)
        }

        // Remember the connection that carries the mirror so room frames reach
        // the host even before it has joined (its peer is not yet a member here).
        if endpoint.isRemote, let owningCode = endpoint.owningConnectionSessionCode {
            agentRoomWiredOwnerConnectionCodesByRoomID[roomID, default: []].insert(owningCode)
        }

        let memberSurfaceID = endpoint.memberSurfaceID
        let hookSession = endpoint.isRemote ? nil : Self.claudeHookSessionRef(surfaceID: memberSurfaceID)
        let member = ClaudeRoomMember(
            surfaceID: memberSurfaceID,
            agentSessionID: hookSession?.sessionID,
            peerID: endpoint.peerID,
            displayName: endpoint.displayName
        )

        if let previousRoomID = endpoint.existingRoomID, previousRoomID != roomID {
            if let previousRoom = await agentRoomStore.disconnect(
                roomID: previousRoomID,
                memberID: agentRoomMemberID(surfaceID: memberSurfaceID, inRoomID: previousRoomID),
                surfaceID: memberSurfaceID
            ) {
                cacheAgentRoom(previousRoom)
                reconcileAgentRoomMembership(with: previousRoom)
                try? await send(.agentRoomSnapshot(previousRoom))
            }
        }

        if !endpoint.isRemote {
            agentRoomIDsBySurfaceID[endpoint.localSurfaceID] = roomID
            agentRoomMemberIDsBySurfaceID[endpoint.localSurfaceID] = member.id
        }
        registerAgentRoomDisplayOrder(roomID: roomID)
        _ = await agentRoomStore.setDeliveryPolicy(roomID: roomID, policy: .semiLive)
        let room = await agentRoomStore.connect(member: member, to: roomID)
        latestAgentRoomID = roomID
        cacheAgentRoom(room)
        reconcileAgentRoomMembership(with: room)

        let broadcastRoom: ClaudeRoomSnapshot
        if endpoint.isRemote {
            broadcastRoom = room
        } else {
            await ingestAgentRoomTranscriptFiles(roomID: roomID, members: room.members)
            broadcastRoom = await backfillAgentRoomLedgerFromTranscripts(
                roomID: roomID,
                joiningSurfaceID: memberSurfaceID,
                room: room
            )
            cacheAgentRoom(broadcastRoom)
        }
        agentRoomHeaderRevision &+= 1
        try? await send(.agentRoomSnapshot(broadcastRoom))
        return broadcastRoom
    }

    private func disconnectAgentRoomEndpoint(
        _ endpoint: AgentRoomWireEndpoint,
        roomID: String
    ) async {
        let room = await agentRoomStore.disconnect(
            roomID: roomID,
            memberID: agentRoomMemberID(surfaceID: endpoint.memberSurfaceID, inRoomID: roomID),
            surfaceID: endpoint.memberSurfaceID
        )
        if !endpoint.isRemote {
            agentRoomIDsBySurfaceID.removeValue(forKey: endpoint.localSurfaceID)
            agentRoomMemberIDsBySurfaceID.removeValue(forKey: endpoint.localSurfaceID)
        } else if let owningCode = endpoint.owningConnectionSessionCode {
            agentRoomWiredOwnerConnectionCodesByRoomID[roomID]?.remove(owningCode)
            if agentRoomWiredOwnerConnectionCodesByRoomID[roomID]?.isEmpty == true {
                agentRoomWiredOwnerConnectionCodesByRoomID.removeValue(forKey: roomID)
            }
        }
        agentRoomHeaderRevision &+= 1
        if let room {
            cacheAgentRoom(room)
            reconcileAgentRoomMembership(with: room)
            try? await send(.agentRoomSnapshot(room))
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
            properties.merge(workspace.mosaicAnalyticsLayoutProperties(snapshotReason: reason)) { _, new in new }
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
        for room in rooms {
            refreshAgentRoomHookHealth(room: room)
        }
        return agentRoomStatusPayloadSnapshot()
    }

    func agentRoomStatusPayloadSnapshot() -> [String: Any] {
        [
            "rooms": agentRoomSnapshotsByID.values.sorted { $0.id < $1.id }.map(agentRoomStatusRoomPayload),
            "latest_room_id": latestAgentRoomID ?? NSNull(),
            "connected": activeConnection != nil,
            "relay_url": relayURLString,
            "session_code": sessionCode ?? NSNull(),
        ]
    }

    /// Room payload enriched with per-member link health: whether the member's
    /// surface has a Claude hook session record on disk (and its transcript
    /// path). A member without one is a dead link — its hooks never registered,
    /// so it neither publishes to nor receives from the room. Exposed through
    /// `mosaic agent-room status` so a silently unplugged agent is diagnosable.
    private func agentRoomStatusRoomPayload(_ room: ClaudeRoomSnapshot) -> [String: Any] {
        var payload = agentRoomPayload(room)
        payload["members"] = room.members.map { member -> [String: Any] in
            var dict = (encodedJSONObject(member) as? [String: Any]) ?? [:]
            let hook = Self.claudeHookSessionRef(surfaceID: member.surfaceID)
            dict["hook_linked"] = hook != nil
            dict["hook_session_id"] = hook?.sessionID ?? NSNull()
            dict["hook_transcript_path"] = hook?.transcriptPath ?? NSNull()
            // Bridge-consent visibility: for a member whose surface is hosted on
            // THIS machine, expose whether the host has granted the terminal-drive
            // consent that gates the agent-room bridge. This is the one gate not
            // otherwise observable, and a common reason a remote wire stays inert.
            if let surfaceUUID = UUID(uuidString: member.surfaceID),
               let terminalID = hostedTerminalIDsBySurfaceID[surfaceUUID] {
                dict["is_local_host"] = true
                if let connection = connection(forTerminalID: terminalID) {
                    dict["bridge_consent_granted"] = hostHasGrantedAgentRoomBridge(
                        terminalID: terminalID,
                        connection: connection
                    )
                } else {
                    dict["bridge_consent_granted"] = NSNull()
                }
            } else {
                dict["is_local_host"] = false
                dict["bridge_consent_granted"] = NSNull()
            }
            return dict
        }
        return payload
    }

    /// Recomputes which locally connected surfaces of a room have no Claude
    /// hook session record and caches the result for the header pill. Called
    /// from membership changes and status/digest refreshes — never from a view
    /// body (the pill reads only the cached set).
    private func refreshAgentRoomHookHealth(room: ClaudeRoomSnapshot) {
        var changed = false
        for member in room.members {
            guard let surfaceUUID = UUID(uuidString: member.surfaceID),
                  agentRoomIDsBySurfaceID[surfaceUUID] == room.id else { continue }
            let degraded = Self.claudeHookSessionRef(surfaceID: member.surfaceID) == nil
            if degraded != agentRoomDegradedSurfaceIDs.contains(surfaceUUID) {
                if degraded {
                    agentRoomDegradedSurfaceIDs.insert(surfaceUUID)
                } else {
                    agentRoomDegradedSurfaceIDs.remove(surfaceUUID)
                }
                changed = true
            }
        }
        if changed {
            agentRoomHeaderRevision &+= 1
        }
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
        let resolvedSurfaceID = resolveAgentRoomSurfaceID(requestedSurfaceID)
        // A mirrored (remote) surface bridges the host's real surface into the
        // room, so route it through the shared endpoint path used by the wire drag
        // and header button rather than registering the agent-less mirror pane.
        if let resolvedSurfaceID, mirroredTerminalIDsBySurfaceID[resolvedSurfaceID] != nil {
            let endpoint = agentRoomWireEndpoint(localSurfaceID: resolvedSurfaceID)
            if endpoint.isStaleMirror {
                return ["connected": false, "error": Self.agentRoomStaleMirrorWireError]
            }
            let roomID = AgentRoomSelection.roomIDForSurfaceConnection(
                requestedRoomID: requestedRoomID,
                surfaceWasExplicit: requestedSurfaceID != nil,
                mappedSurfaceRoomID: endpoint.existingRoomID,
                latestRoomID: latestAgentRoomID,
                newRoomID: UUID().uuidString
            )
            if let room = await connectAgentRoomEndpoint(endpoint, roomID: roomID) {
                return agentRoomPayload(room)
            }
            return ["connected": false, "error": "Could not bridge the remote terminal into a room."]
        }
        let roomID = AgentRoomSelection.roomIDForSurfaceConnection(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: requestedSurfaceID != nil,
            mappedSurfaceRoomID: resolvedSurfaceID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID,
            newRoomID: UUID().uuidString
        )
        if await agentRoomStore.room(id: roomID) == nil {
            let room = await agentRoomStore.createRoom(id: roomID)
            cacheAgentRoom(room)
            registerAgentRoomDisplayOrder(roomID: roomID)
        }
        guard let surfaceID = resolvedSurfaceID else {
            return ["connected": false, "error": "No terminal surface is available."]
        }
        let hookSession = Self.claudeHookSessionRef(surfaceID: surfaceID.uuidString)
        let member = ClaudeRoomMember(
            surfaceID: surfaceID.uuidString,
            agentSessionID: agentSessionID ?? hookSession?.sessionID,
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
        registerAgentRoomDisplayOrder(roomID: roomID)
        _ = await agentRoomStore.setDeliveryPolicy(roomID: roomID, policy: .semiLive)
        let room = await agentRoomStore.connect(member: member, to: roomID)
        latestAgentRoomID = roomID
        cacheAgentRoom(room)
        reconcileAgentRoomMembership(with: room)
        await ingestAgentRoomTranscriptFiles(roomID: roomID, members: room.members)
        let backfilledRoom = await backfillAgentRoomLedgerFromTranscripts(
            roomID: roomID,
            joiningSurfaceID: surfaceID.uuidString,
            room: room
        )
        cacheAgentRoom(backfilledRoom)
        try? await send(.agentRoomSnapshot(backfilledRoom))
        return agentRoomPayload(backfilledRoom)
    }

    /// Promotes each member's recently ingested transcript turns into deduped
    /// `.message` ledger events at wire time, so a freshly joined peer
    /// deterministically syncs the prior conversation (including messages typed
    /// before it was wired) on its next turn or prompt.
    ///
    /// The joining member's acknowledgment cursor is left untouched so its next
    /// `agent.room.consume` / digest surfaces the backfilled backlog. Every
    /// pre-existing member's cursor is advanced past the backfill so they are not
    /// re-interrupted with history they already have.
    private func backfillAgentRoomLedgerFromTranscripts(
        roomID: String,
        joiningSurfaceID: String,
        room: ClaudeRoomSnapshot
    ) async -> ClaudeRoomSnapshot {
        await promoteTranscriptTurnsToLedger(roomID: roomID, members: room.members)
        guard let updatedRoom = await agentRoomStore.room(id: roomID) else { return room }
        // Existing peers already have this history; only the joining peer catches up.
        for member in updatedRoom.members where member.surfaceID != joiningSurfaceID {
            _ = await agentRoomStore.acknowledge(
                roomID: roomID,
                memberID: member.id,
                sequence: updatedRoom.lastSequence
            )
        }
        return await agentRoomStore.room(id: roomID) ?? updatedRoom
    }

    /// Promotes each member's recently ingested transcript turns into deduped
    /// `.message` ledger events: a turn becomes a room event exactly once
    /// (keyed by the transcript `sourceID`), and `consumePendingEvents`'
    /// cursor then delivers it to each peer at most once. Turns are ingested
    /// deterministically from transcript files at wire time
    /// (`ingestAgentRoomTranscriptFiles`), so re-wiring never duplicates
    /// events and never depends on live session bindings being warm.
    private func promoteTranscriptTurnsToLedger(
        roomID: String,
        members: [ClaudeRoomMember]
    ) async {
        for member in members {
            let turns = await agentRoomStore.transcriptTurns(
                roomID: roomID,
                surfaceID: member.surfaceID,
                limit: agentRoomBackfillTurnsPerMember
            )
            for turn in turns {
                let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // Stable dedup key: prefer the transcript's own source id, else a
                // composed key from the room transcript index sequence so re-wiring
                // or a re-ingest never duplicates the same turn.
                let sourceID = turn.sourceID
                    ?? "transcript:\(roomID):\(member.surfaceID):\(turn.sequence)"
                _ = await agentRoomStore.appendEvent(
                    roomID: roomID,
                    kind: .message,
                    fromMemberID: member.id,
                    fromSurfaceID: member.surfaceID,
                    text: text,
                    sourceID: sourceID
                )
            }
        }
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

    func resetAgentRoomForAutomation(roomID requestedRoomID: String?) async -> [String: Any] {
        if let requestedRoomID {
            let removed = await agentRoomStore.removeRoom(id: requestedRoomID)
            guard let removed else {
                agentRoomSnapshotsByID.removeValue(forKey: requestedRoomID)
                if latestAgentRoomID == requestedRoomID {
                    latestAgentRoomID = nil
                }
                return ["reset": false, "error": "Claude room not found.", "room_id": requestedRoomID]
            }
            for member in removed.members {
                if let surfaceID = UUID(uuidString: member.surfaceID) {
                    agentRoomIDsBySurfaceID.removeValue(forKey: surfaceID)
                    agentRoomMemberIDsBySurfaceID.removeValue(forKey: surfaceID)
                    agentRoomDegradedSurfaceIDs.remove(surfaceID)
                }
            }
            agentRoomSnapshotsByID.removeValue(forKey: requestedRoomID)
            agentRoomWiredOwnerConnectionCodesByRoomID.removeValue(forKey: requestedRoomID)
            if latestAgentRoomID == requestedRoomID {
                latestAgentRoomID = nil
            }
            removeAgentRoomDisplayOrder(roomID: requestedRoomID)
            agentRoomHeaderRevision &+= 1
            return ["reset": true, "room_id": requestedRoomID]
        }

        await agentRoomStore.clearAllRooms()
        agentRoomIDsBySurfaceID.removeAll()
        agentRoomMemberIDsBySurfaceID.removeAll()
        agentRoomSnapshotsByID.removeAll()
        agentRoomWiredOwnerConnectionCodesByRoomID.removeAll()
        agentRoomDegradedSurfaceIDs.removeAll()
        latestAgentRoomID = nil
        agentRoomDisplayOrder = []
        agentRoomHeaderRevision &+= 1
        return ["reset": true, "all": true]
    }

    func resetAgentRoomForAutomationRequest(roomID: String?) -> [String: Any] {
        Task { @MainActor in
            _ = await resetAgentRoomForAutomation(roomID: roomID)
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
        if rawFromSurfaceID != nil {
            await restorePersistedAgentRoomMembershipIfNeeded(surfaceID: fromSurfaceUUID)
        }
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: rawFromSurfaceID != nil,
            mappedSurfaceRoomID: fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
        guard let roomID else {
            #if DEBUG
            mosaicDebugLog("agentRoom.post dropped: no active room (from raw=\(rawFromSurfaceID ?? "nil") resolved=\(fromSurfaceUUID?.uuidString ?? "nil"))")
            #endif
            return [
                "posted": false,
                "error": "No Claude room is active.",
                "from_surface_resolved": fromSurfaceUUID?.uuidString ?? NSNull(),
            ]
        }
        let kind = rawKind.flatMap(ClaudeRoomEventKind.init(rawValue:)) ?? .message
        let fromSurfaceID = fromSurfaceUUID?.uuidString ?? rawFromSurfaceID
        let fromMemberID = fromSurfaceUUID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        #if DEBUG
        if fromSurfaceUUID.flatMap({ agentRoomIDsBySurfaceID[$0] }) != roomID {
            mosaicDebugLog("agentRoom.post: from surface \(fromSurfaceID ?? "nil") is not a mapped member of room \(roomID); event still posts but peers may be unreachable")
        }
        #endif
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
        // Delivery is invisible and pull-based: peers consume pending events via
        // their own Claude hooks (Stop / UserPromptSubmit). Nothing is typed into
        // any terminal here.
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
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: rawFromSurfaceID != nil,
            mappedSurfaceRoomID: fromSurfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
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
        if rawSurfaceID != nil {
            await restorePersistedAgentRoomMembershipIfNeeded(surfaceID: surfaceUUID)
        }
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: rawSurfaceID != nil,
            mappedSurfaceRoomID: surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
        guard let roomID, let room = await agentRoomStore.room(id: roomID) else {
            return ["digest": "", "error": "Claude room not found."]
        }
        let contextPackText = await peerAgentRoomContextText(
            roomID: roomID,
            room: room,
            recipientSurfaceID: surfaceUUID?.uuidString,
            maxEvents: 0
        )
        cacheAgentRoom(room)
        return agentRoomDigestPayload(
            room: room,
            surfaceID: surfaceUUID?.uuidString,
            since: since,
            contextPackText: contextPackText
        )
    }

    func agentRoomDigestPayloadSnapshot(roomID requestedRoomID: String?, surfaceID rawSurfaceID: String? = nil, since: Int?) -> [String: Any] {
        let surfaceUUID = resolveAgentRoomSurfaceID(rawSurfaceID)
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: rawSurfaceID != nil,
            mappedSurfaceRoomID: surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
        guard let roomID, let room = agentRoomSnapshotsByID[roomID] else {
            return ["digest": "", "error": "Claude room not found."]
        }
        return agentRoomDigestPayload(room: room, surfaceID: surfaceUUID?.uuidString, since: since)
    }

    private func agentRoomDigestPayload(
        room: ClaudeRoomSnapshot,
        surfaceID: String?,
        since: Int?,
        contextPackText: String = ""
    ) -> [String: Any] {
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
            "context_pack_text": contextPackText,
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

    /// Drains anything shared with the given surface since it last consumed, and
    /// returns it as ready-to-inject prompt text (empty when nothing pending).
    ///
    /// This is the invisible pull-based delivery path: a peer's own Claude hook
    /// (Stop or UserPromptSubmit) calls `agent.room.consume`, which advances the
    /// acknowledgment cursor so each message reaches a peer at most once. Nothing
    /// is typed into any terminal. Delivery is gated on the room being in the
    /// broadcast (`semiLive`) policy that wiring sets, and only broadcastable
    /// kinds (plain messages plus targeted handoff/question/blocker) are folded in;
    /// ledger-only kinds (summaries, status, etc.) are consumed but never injected.
    func agentRoomConsumePendingForAutomation(surfaceID rawSurfaceID: String?) async -> [String: Any] {
        let surfaceUUID = resolveAgentRoomSurfaceID(rawSurfaceID)
        if rawSurfaceID != nil {
            await restorePersistedAgentRoomMembershipIfNeeded(surfaceID: surfaceUUID)
        }
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: nil,
            surfaceWasExplicit: rawSurfaceID != nil,
            mappedSurfaceRoomID: surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
        guard let roomID, let room = await agentRoomStore.room(id: roomID) else {
            return ["text": ""]
        }
        let recipientSurfaceID = surfaceUUID?.uuidString
        let memberID = surfaceUUID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        let policy = room.deliveryPolicy
        guard policy == .semiLive else {
            // Not a wired/broadcast room: still advance the cursor so a later switch
            // to broadcast does not replay old backlog, but inject nothing.
            _ = await agentRoomStore.consumePendingEvents(
                roomID: roomID,
                memberID: memberID,
                surfaceID: recipientSurfaceID
            )
            return ["text": ""]
        }
        // Consume drains only pushed ledger events. Live content is pushed by
        // each agent's own hooks (UserPromptSubmit posts the prompt, Stop posts
        // the reply summary) and pre-wire history enters via the wire-time file
        // backfill, so there is deliberately no transcript scraping here: it runs
        // on every prompt and must stay cheap and deterministic.
        let pending = await agentRoomStore.consumePendingEvents(
            roomID: roomID,
            memberID: memberID,
            surfaceID: recipientSurfaceID
        )
        let prompts = pending.compactMap { event in
            agentRoomActiveDispatchPromptBuilder.broadcastPrompt(for: event, policy: policy)
        }
        return ["text": prompts.joined(separator: "\n\n")]
    }

    /// Builds a full room recap for a surface whose Claude session just
    /// (re)started, and advances that member's acknowledgment cursor to the
    /// room's latest sequence.
    ///
    /// This is the restart-amnesia fix: a resumed/cleared Claude session has
    /// lost whatever was injected into its predecessor, but the persisted
    /// ledger still knows the room history. The `SessionStart` hook injects
    /// this recap invisibly via `additionalContext`; resetting the cursor here
    /// keeps the next `agent.room.consume` from re-delivering the same events
    /// as increments.
    ///
    /// Transcript files are re-ingested and promoted first so the recap is
    /// self-sufficient even when a member's push hooks never fired (the exact
    /// silent failure that motivated the deterministic file path).
    func agentRoomRecapForAutomation(surfaceID rawSurfaceID: String?) async -> [String: Any] {
        let surfaceUUID = resolveAgentRoomSurfaceID(rawSurfaceID)
        if rawSurfaceID != nil {
            await restorePersistedAgentRoomMembershipIfNeeded(surfaceID: surfaceUUID)
        }
        let roomID = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: nil,
            surfaceWasExplicit: rawSurfaceID != nil,
            mappedSurfaceRoomID: surfaceUUID.flatMap { agentRoomIDsBySurfaceID[$0] },
            latestRoomID: latestAgentRoomID
        )
        guard let roomID, let room = await agentRoomStore.room(id: roomID) else {
            return ["text": ""]
        }
        let recipientSurfaceID = surfaceUUID?.uuidString
        await ingestAgentRoomTranscriptFiles(roomID: roomID, members: room.members)
        await promoteTranscriptTurnsToLedger(roomID: roomID, members: room.members)
        guard let refreshed = await agentRoomStore.room(id: roomID) else {
            return ["text": ""]
        }
        // Peer content only: the restarting agent's own turns either survived
        // its own --resume or were intentionally cleared.
        let recapRoom: ClaudeRoomSnapshot
        if let recipientSurfaceID {
            var filtered = refreshed
            filtered.events = refreshed.events.filter { event in
                event.fromSurfaceID != recipientSurfaceID &&
                    (event.targetSurfaceIDs.isEmpty || event.targetSurfaceIDs.contains(recipientSurfaceID))
            }
            recapRoom = filtered
        } else {
            recapRoom = refreshed
        }
        let recap = agentRoomDigestBuilder.digest(for: recapRoom)
        // The recap covers everything up to lastSequence; consuming acknowledges
        // exactly that range so prompt-time delivery starts fresh from here.
        let memberID = surfaceUUID.flatMap { agentRoomMemberIDsBySurfaceID[$0] }
        _ = await agentRoomStore.consumePendingEvents(
            roomID: roomID,
            memberID: memberID,
            surfaceID: recipientSurfaceID
        )
        if let synced = await agentRoomStore.room(id: roomID) {
            cacheAgentRoom(synced)
        }
        return ["text": recap, "room_id": roomID]
    }

    /// Reads each member's Claude transcript JSONL file straight off disk (path
    /// recorded by the hook session store) and ingests the recent turns into
    /// the room's transcript index, deduped by `sourceID`.
    ///
    /// Deterministic by design: this replaced the live-session/tailer scrape
    /// (`resolveLiveSession` + `history`) whose warm-up races at wire time
    /// silently dropped pre-wire messages from the shared room.
    private func ingestAgentRoomTranscriptFiles(roomID: String, members: [ClaudeRoomMember]) async {
        let now = Date()
        let cutoff = now.addingTimeInterval(-agentRoomBackfillFreshnessWindow)
        for member in members {
            guard let ref = Self.claudeHookSessionRef(surfaceID: member.surfaceID),
                  let transcriptPath = ref.transcriptPath else { continue }
            let fileURL = URL(fileURLWithPath: transcriptPath)
            let parsedTurns = ClaudeTranscriptFileParser.parseTurns(
                fileURL: fileURL,
                limit: agentRoomTranscriptHistoryLimit
            )
            // Bound backfill to recent turns so a long-lived/reused session's
            // transcript file cannot drag ancient conversation into a freshly
            // created room. Untimestamped turns fall back to the file's own
            // modification date, so a stale file is excluded wholesale.
            let fileModifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            let turns = ClaudeTranscriptFileParser.recentTurns(
                parsedTurns,
                notOlderThan: cutoff,
                fallbackDate: fileModifiedAt
            )
            for turn in turns {
                _ = await agentRoomStore.appendTranscriptTurn(
                    roomID: roomID,
                    agentKind: "claude",
                    memberID: member.id,
                    surfaceID: member.surfaceID,
                    role: turn.role,
                    text: truncatedAgentRoomTranscriptText(turn.text),
                    sourceID: "\(ref.sessionID):\(turn.id)",
                    createdAt: turn.timestamp ?? Date()
                )
            }
        }
    }

    struct ClaudeHookSessionRef {
        let sessionID: String
        let transcriptPath: String?
        let updatedAt: TimeInterval
    }

    /// Resolves the Claude hook session to bind a surface to, straight from the
    /// on-disk hook store (`~/.mosaicterm/claude-hook-sessions.json`, written by
    /// `mosaic hooks claude ...`).
    ///
    /// Prefers the surface's *currently active* session (the live Claude that
    /// last drove hooks in that pane) so wiring binds to the running agent
    /// rather than a stale session that merely lingers in the store. Falls back
    /// to the newest session that carries a transcript path.
    static func claudeHookSessionRef(surfaceID: String) -> ClaudeHookSessionRef? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mosaicterm", isDirectory: true)
            .appendingPathComponent("claude-hook-sessions.json", isDirectory: false)
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let sessions = (root["sessions"] as? [String: Any]) ?? root
        func ref(forSessionID sessionID: String) -> ClaudeHookSessionRef? {
            guard let entry = sessions[sessionID] as? [String: Any] else { return nil }
            return ClaudeHookSessionRef(
                sessionID: sessionID,
                transcriptPath: (entry["transcriptPath"] as? String)?.nilIfEmpty,
                updatedAt: (entry["updatedAt"] as? TimeInterval) ?? 0
            )
        }
        // The live session for this pane, if the store tracks one, wins so long
        // as it has a transcript to read.
        if let activeBySurface = root["activeSessionsBySurface"] as? [String: Any],
           let activeEntry = activeBySurface[surfaceID] as? [String: Any],
           let activeSessionID = (activeEntry["sessionId"] as? String)?.nilIfEmpty,
           let activeRef = ref(forSessionID: activeSessionID),
           activeRef.transcriptPath != nil {
            return activeRef
        }
        let candidates = sessions.compactMap { sessionID, value -> ClaudeHookSessionRef? in
            guard let entry = value as? [String: Any],
                  (entry["surfaceId"] as? String) == surfaceID else {
                return nil
            }
            return ClaudeHookSessionRef(
                sessionID: sessionID,
                transcriptPath: (entry["transcriptPath"] as? String)?.nilIfEmpty,
                updatedAt: (entry["updatedAt"] as? TimeInterval) ?? 0
            )
        }
        return candidates.max { lhs, rhs in
            (lhs.transcriptPath != nil ? 1 : 0, lhs.updatedAt) < (rhs.transcriptPath != nil ? 1 : 0, rhs.updatedAt)
        }
    }

    private func peerAgentRoomContextText(
        roomID: String,
        room: ClaudeRoomSnapshot,
        recipientSurfaceID: String?,
        maxEvents: Int = 0
    ) async -> String {
        let recipientMemberID = recipientSurfaceID.flatMap { surfaceID in
            room.members.first(where: { $0.surfaceID == surfaceID })?.id
        }
        let pack = await agentRoomStore.peerContextPack(
            roomID: roomID,
            recipientMemberID: recipientMemberID,
            recipientSurfaceID: recipientSurfaceID,
            maxEvents: maxEvents,
            maxTranscriptTurns: agentRoomContextPackTranscriptLimit
        )
        return pack?.promptText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func truncatedAgentRoomTranscriptText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > agentRoomTranscriptTurnCharacterLimit else { return trimmed }
        return String(trimmed.prefix(agentRoomTranscriptTurnCharacterLimit)) + "..."
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
        terminalOwnerAvatarRequestKeysByID.removeAll()
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
        hostedTerminalDimensionsProbedAtByID.removeAll()
        mirroredTerminalsByID.removeAll()
        mirroredTerminalIDsBySurfaceID.removeAll()
        mirroredTerminalRenderGridPatchSequencesByID.removeAll()
        mirroredTerminalRenderGridSequencesByID.removeAll()
        pendingMirroredRenderGridFramesByID.removeAll()
        echoLastApplyAtByID.removeAll()
        mirroredRenderGridSeedRequestTasksByID.values.forEach { $0.cancel() }
        mirroredRenderGridSeedRequestTasksByID.removeAll()
        mirroredTerminalGridLockedIDs.removeAll()
        pendingMirroredFramesAwaitingLockByID.removeAll()
        mirroredGridLockFlushTasksByID.values.forEach { $0.cancel() }
        mirroredGridLockFlushTasksByID.removeAll()
        mirroredTerminalLockedGridByID.removeAll()
        mirroredReseedRequestTasksByID.values.forEach { $0.cancel() }
        mirroredReseedRequestTasksByID.removeAll()
        mirroredContentAppliedUnlockedIDs.removeAll()
        hostedTerminalReseedTasksByID.values.forEach { $0.cancel() }
        hostedTerminalReseedTasksByID.removeAll()
        hostedTerminalLastReseedAtByID.removeAll()
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
        // Directory-sharing orgs never see the create-or-join chooser: the
        // session is created silently and the teammate picker is the sharing
        // surface (createSessionAndShare presents it post-create).
        if collaborationEntitlements.directorySharing {
            Task { await createSessionAndShare(panel: panel) }
            return
        }
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
        // Directory-sharing orgs skip the chooser; see the document variant.
        if collaborationEntitlements.directorySharing {
            Task { await createSessionAndShare(terminal: terminal) }
            return
        }
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
        let panel = CollaborationJoinSessionPanel()
        guard let rawCode = panel.run() else { return nil }
        let code = Self.normalizedSessionCode(from: rawCode)
        return code.isEmpty ? nil : code
    }

    private func configureCollaborationAlertChrome(_ alert: NSAlert) {
        alert.icon = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
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
            // Documents connect before this point, so the session is already
            // live: route directory plans through the guarded teammate picker
            // and codes plans through the shareable-code dialog.
            if collaborationEntitlements.directorySharing {
                presentTeammateDirectorySharePicker()
            } else {
                presentCreatedSessionDialog(code: response.sessionCode)
            }
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
        if collaborationEntitlements.directorySharing {
            // Team/enterprise: the teammate picker is the first-class create
            // surface. Present it immediately from the warm directory cache
            // while session create + relay connect run concurrently, so the
            // NSAlert is no longer gated behind connect latency (previously the
            // picker only appeared after the up-to-5s join-ack wait). The invite
            // is sent only once the session is ready — see the picker.
            let sessionTask = Task<Bool, Never> { @MainActor [weak self] in
                guard let self else { return false }
                _ = await self.performCreateSessionConnectShare(terminal: terminal)
                return self.activeConnection != nil
            }
            presentTeammateDirectorySharePicker(pendingSession: sessionTask)
        } else {
            let response = await performCreateSessionConnectShare(terminal: terminal)
            if let response {
                presentCreatedSessionDialog(code: response.sessionCode)
            }
        }
    }

    /// Create a session, connect to the relay, and share the terminal. Returns
    /// the created-session response (nil only when session creation itself
    /// failed). Analytics and error handling live here so both the codes and
    /// directory create paths behave identically; the directory path runs this
    /// concurrently with the teammate picker.
    @discardableResult
    private func performCreateSessionConnectShare(terminal: TerminalPanel) async -> CollaborationCreateSessionResponse? {
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
            return response
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
            return nil
        }
    }

    private func presentCreatedSessionDialog(code: String) {
        let normalizedCode = Self.normalizedSessionCode(from: code)
        let panel = CollaborationSessionCreatedPanel(code: normalizedCode)
        guard panel.run() == .alertFirstButtonReturn else { return }
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
        await acquireCodeJoinGrantIfPossible(code: normalizedCode)
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
        // Preferred path: www is authoritative. It checks the org plan, mints a
        // signed session descriptor + owner join grant, and returns the relay
        // room/code. Falls back to the legacy relay create when the user has no
        // resolvable org/token or the backend is unavailable.
        if let created = (try? await createSessionViaBackend()) ?? nil {
            return created
        }
        return try await createSessionViaRelay()
    }

    private func createSessionViaBackend() async throws -> CollaborationCreateSessionResponse? {
        await refreshPeerIdentityForCollaborationAdvertise()
        guard let orgID = resolvedCollaborationOrgID,
              let token = await collaborationAccessToken() else { return nil }
        // Create the relay room from THIS machine first. Cloudflare places a
        // session's Durable Object near whoever first creates it; when www
        // created the room from its own region, every keystroke and echo of
        // every session detoured through that far colo (~85ms each way,
        // measured), which read as typing lag on shared terminals. www reuses
        // the pre-created code and still does all auth/grant work; if the
        // relay is unreachable (or www predates the `code` parameter), www
        // falls back to creating the room itself exactly as before.
        let precreatedCode = (try? await createSessionViaRelay())?.sessionCode
        let created = try await collaborationBackendClient.createSession(
            accessToken: token,
            orgId: orgID,
            relayURL: relayURLString,
            precreatedCode: precreatedCode
        )
        applyBackendCreatedSession(created)
        return CollaborationCreateSessionResponse(
            sessionID: created.room,
            sessionCode: created.code ?? created.room
        )
    }

    private func applyBackendCreatedSession(_ created: CollaborationCreatedSession) {
        if !created.relayURL.isEmpty {
            relayURLString = Self.normalizedRelayURL(from: created.relayURL)
        }
        collaborationEntitlements = created.entitlements
        prefetchDirectoryMembersIfNeeded()
        storeGrant(created.grant, forRoom: created.room)
        let roomKey = normalizedRoomKey(created.room)
        sessionDescriptorsByRoom[roomKey] = created.session
        // Persist so an explicit session-end after an app relaunch can still
        // withdraw the invites we sent (in-memory maps are lost on relaunch).
        Self.outgoingInviteStore.recordDescriptor(created.session, forRoomKey: roomKey)
    }

    private func createSessionViaRelay() async throws -> CollaborationCreateSessionResponse {
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

    // MARK: - Collaboration backend (www) integration

    private var collaborationBackendClient: CollaborationBackendClient {
        CollaborationBackendClient(baseURL: AuthEnvironment.apiBaseURL)
    }

    private var resolvedCollaborationOrgID: String? {
        AppDelegate.shared?.auth?.coordinator.resolvedTeamID
    }

    private func collaborationAccessToken() async -> String? {
        guard let coordinator = AppDelegate.shared?.auth?.coordinator else { return nil }
        return try? await coordinator.accessToken()
    }

    private func normalizedRoomKey(_ room: String) -> String {
        Self.normalizedSessionCode(from: room)
    }

    private func storeGrant(_ grant: String, forRoom room: String) {
        grantsByRoom[normalizedRoomKey(room)] = grant
        grantsByRoom[room] = grant
    }

    private func grant(forRoom room: String) -> String? {
        grantsByRoom[normalizedRoomKey(room)] ?? grantsByRoom[room]
    }

    /// Before joining by code, ask www for a signed grant so the relay admits
    /// the connection once grants are enforced. Legacy relays accept code-only
    /// joins, so a failure here is non-fatal.
    private func acquireCodeJoinGrantIfPossible(code: String) async {
        guard grant(forRoom: code) == nil,
              let token = await collaborationAccessToken() else { return }
        do {
            let result = try await collaborationBackendClient.joinByCode(
                accessToken: token,
                code: code,
                relayURL: relayURLString
            )
            if !result.relayURL.isEmpty {
                relayURLString = Self.normalizedRelayURL(from: result.relayURL)
            }
            storeGrant(result.grant, forRoom: result.room)
        } catch {
            // Non-fatal: proceed without a grant (legacy code-only join).
        }
    }

    /// React to the active org (`AuthCoordinator.resolvedTeamID`) changing —
    /// e.g. the user switching teams in Settings. Drops the previous org's
    /// directory-member cache and re-resolves entitlements so the session-
    /// sharing UI (directory vs codes) tracks the newly active org. Deduped on
    /// the resolved org id so redundant observation notifications (an
    /// `availableTeams` refresh that leaves the resolved id unchanged) are
    /// no-ops. Cloud/VM calls read `resolvedTeamID` live per request, so they
    /// need no explicit refresh here.
    func handleActiveCollaborationOrgChanged() async {
        let orgID = resolvedCollaborationOrgID
        guard orgID != lastEntitlementsOrgID else { return }
        lastEntitlementsOrgID = orgID
        directoryMemberCacheByOrgID.removeAll()
        await refreshCollaborationEntitlements()
    }

    /// Refresh the org's sharing entitlements (plan, directory sharing, codes).
    func refreshCollaborationEntitlements() async {
        guard let orgID = resolvedCollaborationOrgID,
              let token = await collaborationAccessToken() else {
            collaborationEntitlements = .hobbyDefault
            return
        }
        if let entitlements = try? await collaborationBackendClient.entitlements(
            accessToken: token,
            orgId: orgID
        ) {
            collaborationEntitlements = entitlements
            prefetchDirectoryMembersIfNeeded()
        }
    }

    /// The org members eligible to receive a directory share (team/enterprise).
    func loadDirectoryMembers() async -> [CollaborationDirectoryMember] {
        guard let orgID = resolvedCollaborationOrgID else { return [] }
        if let cached = directoryMemberCacheByOrgID[orgID] {
            if Date().timeIntervalSince(cached.fetchedAt) > Self.directoryMemberCacheTTL {
                prefetchDirectoryMembers(orgID: orgID)
            }
            return cached.members
        }
        return await refreshDirectoryMembers(orgID: orgID)
    }

    private func prefetchDirectoryMembersIfNeeded() {
        guard collaborationEntitlements.directorySharing,
              let orgID = resolvedCollaborationOrgID else { return }
        if let cached = directoryMemberCacheByOrgID[orgID],
           Date().timeIntervalSince(cached.fetchedAt) <= Self.directoryMemberCacheTTL {
            return
        }
        prefetchDirectoryMembers(orgID: orgID)
    }

    private func prefetchDirectoryMembers(orgID: String) {
        guard directoryMemberRefreshTasksByOrgID[orgID] == nil else { return }
        Task { @MainActor [weak self] in
            _ = await self?.refreshDirectoryMembers(orgID: orgID)
        }
    }

    private func refreshDirectoryMembers(orgID: String) async -> [CollaborationDirectoryMember] {
        if let existing = directoryMemberRefreshTasksByOrgID[orgID] {
            return await existing.value
        }
        let task = Task<[CollaborationDirectoryMember], Never> { @MainActor [weak self] in
            guard let self,
                  let token = await self.collaborationAccessToken() else { return [] }
            let members = (try? await self.collaborationBackendClient.directory(
                accessToken: token,
                orgId: orgID
            )) ?? []
            self.directoryMemberCacheByOrgID[orgID] = DirectoryMemberCacheEntry(
                members: members,
                fetchedAt: Date()
            )
            return members
        }
        directoryMemberRefreshTasksByOrgID[orgID] = task
        let members = await task.value
        directoryMemberRefreshTasksByOrgID[orgID] = nil
        return members
    }

    /// Share the currently active session with a teammate by user id. The
    /// teammate receives it in their incoming-sessions inbox (no code).
    @discardableResult
    func shareCurrentSessionWithTeammate(userID: String) async -> Bool {
        guard let connection = activeConnection else { return false }
        await refreshPeerIdentityForCollaborationAdvertise()
        let descriptor = sessionDescriptorsByRoom[normalizedRoomKey(connection.sessionCode)]
            ?? sessionDescriptorsByRoom[connection.sessionCode]
        guard let descriptor else { return false }
        guard let token = await collaborationAccessToken() else { return false }
        do {
            try await collaborationBackendClient.invite(
                accessToken: token,
                session: descriptor,
                inviteeUserId: userID,
                relayURL: relayURLString
            )
            let roomKey = normalizedRoomKey(connection.sessionCode)
            invitedTeammateUserIDsByRoom[roomKey, default: []].insert(userID)
            Self.outgoingInviteStore.addInvitee(userID, forRoomKey: roomKey, descriptor: descriptor)
            await notifyInboxRealtime(inviteeUserID: userID)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Withdraw every directory invite we sent for `room` so a teammate's inbox
    /// stops surfacing an invite for a session that has ended, then clear the
    /// local descriptor / grant / invitee bookkeeping for that room. Called from
    /// the session-end paths (not single-terminal unshare, which may leave the
    /// session live for other terminals/peers).
    private func withdrawTeammateInvites(forRoom room: String) {
        let key = normalizedRoomKey(room)
        // Merge the durable record with in-memory state so an end after relaunch
        // (when the in-memory maps are empty) can still withdraw the invites.
        let persisted = Self.outgoingInviteStore.remove(forRoomKey: key)
        let descriptor = sessionDescriptorsByRoom[key]
            ?? sessionDescriptorsByRoom[room]
            ?? persisted?.descriptor
        var invitedUserIDs = invitedTeammateUserIDsByRoom[key] ?? []
        if let persisted { invitedUserIDs.formUnion(persisted.inviteeUserIDs) }
        invitedTeammateUserIDsByRoom.removeValue(forKey: key)
        sessionDescriptorsByRoom.removeValue(forKey: key)
        sessionDescriptorsByRoom.removeValue(forKey: room)
        grantsByRoom.removeValue(forKey: key)
        grantsByRoom.removeValue(forKey: room)
        guard let descriptor, !invitedUserIDs.isEmpty else { return }
        Task { @MainActor [invitedUserIDs, descriptor] in
            guard let token = await collaborationAccessToken() else { return }
            for userID in invitedUserIDs {
                try? await collaborationBackendClient.withdraw(
                    accessToken: token,
                    session: descriptor,
                    inviteeUserId: userID
                )
                // Nudge the teammate to refetch immediately (parity with invite),
                // so the withdrawn invite disappears without waiting for the poll.
                await notifyInboxRealtime(inviteeUserID: userID)
            }
        }
    }

    /// Fetch the incoming shared-session inbox for this user.
    func refreshIncomingSharedSessions() async {
        guard let token = await collaborationAccessToken() else {
            clearIncomingSharedSessions()
            return
        }
        if let invites = try? await collaborationBackendClient.inbox(accessToken: token) {
            applyIncomingInvites(invites)
        }
    }

    /// Reconcile the incoming inbox against the relay so ended sessions are
    /// pruned server-side, then apply the surviving list. Used when the user
    /// opens the picker so the badge and picker only show joinable sessions.
    /// Falls back to a plain inbox refresh when reconcile is unavailable.
    func reconcileIncomingSharedSessions() async {
        guard let token = await collaborationAccessToken() else {
            clearIncomingSharedSessions()
            return
        }
        if let invites = try? await collaborationBackendClient.reconcileInbox(accessToken: token) {
            applyIncomingInvites(invites)
        } else {
            await refreshIncomingSharedSessions()
        }
    }

    private func clearIncomingSharedSessions() {
        incomingSharedSessions = []
        seenIncomingSessionIDs = []
        incomingInviteAlert = nil
        publishIncomingInviteCount()
        publishIncomingInviteAlert()
    }

    private func applyIncomingInvites(_ invites: [CollaborationIncomingSession]) {
        let previouslySeen = seenIncomingSessionIDs
        let currentIDs = Set(invites.map(\.session))
        let previousCount = incomingSharedSessions.count
        incomingSharedSessions = invites
        seenIncomingSessionIDs = currentIDs
        if invites.count != previousCount {
            publishIncomingInviteCount()
        }
        // Auto-surface only genuinely new invites, so a routine refetch of an
        // invite the user already saw does not re-pop the alert.
        if let latestNew = invites.first(where: { !previouslySeen.contains($0.session) }) {
            incomingInviteAlert = latestNew
            incomingInviteAlertToken &+= 1
            publishIncomingInviteAlert()
        } else if let current = incomingInviteAlert, !currentIDs.contains(current.session) {
            // The pending alert was accepted or withdrawn elsewhere; clear it.
            incomingInviteAlert = nil
            publishIncomingInviteAlert()
        }
    }

    /// Dismiss the auto-surfaced invite alert without joining. The invite stays
    /// in the inbox (badge/popover) until accepted or withdrawn.
    func dismissIncomingInviteAlert() {
        incomingInviteAlert = nil
        publishIncomingInviteAlert()
    }

    private func publishIncomingInviteCount() {
        NotificationCenter.default.post(
            name: .collaborationIncomingInviteCountDidChange,
            object: nil,
            userInfo: ["count": incomingSharedSessions.count]
        )
    }

    private func publishIncomingInviteAlert() {
        var userInfo: [String: Any] = [:]
        if let incomingInviteAlert {
            userInfo["invite"] = incomingInviteAlert
        }
        NotificationCenter.default.post(
            name: .collaborationIncomingInviteAlertDidChange,
            object: nil,
            userInfo: userInfo
        )
    }

    /// Accept an incoming shared session: swap the descriptor for a join grant
    /// and connect to the relay room.
    @discardableResult
    func acceptIncomingSharedSession(_ invite: CollaborationIncomingSession) async -> Bool {
        guard let token = await collaborationAccessToken() else { return false }
        do {
            let result = try await collaborationBackendClient.joinByDescriptor(
                accessToken: token,
                session: invite.session,
                relayURL: invite.relayURL
            )
            if !result.relayURL.isEmpty {
                relayURLString = Self.normalizedRelayURL(from: result.relayURL)
            }
            storeGrant(result.grant, forRoom: result.room)
            let connection = await connect(sessionID: result.room, code: result.code ?? result.room)
            removeIncomingInvite(session: invite.session)
            return connection != nil
        } catch {
            lastErrorMessage = error.localizedDescription
            // The session no longer exists (ended/withdrawn) or we were never
            // invited: prune the stale invite locally so it stops surfacing in
            // the badge and picker instead of failing on every attempt.
            if Self.joinFailureMeansInviteGone(error) {
                removeIncomingInvite(session: invite.session)
            }
            return false
        }
    }

    /// Removes an invite from the local inbox and reconciles the badge + any
    /// auto-surfaced alert. Used on both a successful join and when a join fails
    /// because the underlying session is gone.
    private func removeIncomingInvite(session: String) {
        let previousCount = incomingSharedSessions.count
        incomingSharedSessions.removeAll { $0.session == session }
        if incomingSharedSessions.count != previousCount {
            publishIncomingInviteCount()
        }
        if incomingInviteAlert?.session == session {
            incomingInviteAlert = nil
            publishIncomingInviteAlert()
        }
    }

    /// Whether a join failure indicates the invite should be pruned locally: the
    /// session ended, was withdrawn, or the descriptor is no longer valid.
    private static func joinFailureMeansInviteGone(_ error: Error) -> Bool {
        guard case let CollaborationBackendError.http(status, code) = error else { return false }
        return CollaborationInboxJoinFailure.indicatesInviteGone(status: status, code: code)
    }

    func startIncomingSharedSessionsPolling() {
        guard incomingSharedSessionsPollTask == nil else { return }
        incomingSharedSessionsPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshIncomingSharedSessions()
                // Realtime relay nudges (startInboxRealtimeSubscription) deliver
                // invites near-instantly; this poll is only a slow safety net for
                // when the WebSocket is down or a nudge was missed while offline.
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopIncomingSharedSessionsPolling() {
        incomingSharedSessionsPollTask?.cancel()
        incomingSharedSessionsPollTask = nil
    }

    // MARK: - Realtime inbox (relay nudge → www refetch)

    /// Opens a persistent relay WebSocket keyed by the signed-in user so invite
    /// alerts arrive in near real time. The relay only signals "check your
    /// inbox"; the authoritative invite list is always refetched from www.
    func startInboxRealtimeSubscription() {
        let userID = AppDelegate.shared?.auth?.coordinator.currentUser?.id
        guard let userID, !userID.isEmpty else {
            stopInboxRealtimeSubscription()
            return
        }
        if inboxRealtimeTask != nil, inboxRealtimeUserID == userID { return }
        stopInboxRealtimeSubscription()
        inboxRealtimeUserID = userID
        inboxRealtimeTask = Task { @MainActor [weak self] in
            await self?.runInboxRealtimeLoop(userID: userID)
        }
    }

    func stopInboxRealtimeSubscription() {
        inboxRealtimeTask?.cancel()
        inboxRealtimeTask = nil
        inboxRealtimeUserID = nil
    }

    private func runInboxRealtimeLoop(userID: String) async {
        var backoff: Duration = .seconds(1)
        while !Task.isCancelled {
            guard let url = inboxConnectURL(userID: userID) else { return }
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            // Reconcile on connect so we never depend solely on a live nudge.
            await refreshIncomingSharedSessions()
            let heartbeat = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    if Task.isCancelled { return }
                    do {
                        try await task.send(.string("{\"type\":\"inbox.heartbeat\"}"))
                    } catch {
                        return
                    }
                }
            }
            let start = ContinuousClock.now
            await receiveInboxMessages(on: task)
            heartbeat.cancel()
            task.cancel(with: .goingAway, reason: nil)
            if Task.isCancelled { return }
            // A long-lived connection resets the backoff; rapid drops back off.
            if ContinuousClock.now - start > .seconds(30) {
                backoff = .seconds(1)
            }
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, .seconds(30))
        }
    }

    private func receiveInboxMessages(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if inboxMessageIsNudge(message) {
                    await refreshIncomingSharedSessions()
                }
            } catch {
                return
            }
        }
    }

    private func inboxMessageIsNudge(_ message: URLSessionWebSocketTask.Message) -> Bool {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return false
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return false
        }
        return type == "inbox.invite"
    }

    private func inboxConnectURL(userID: String) -> URL? {
        guard var components = URLComponents(string: relayURLString) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/v1/collaboration/inbox/connect"
        components.queryItems = [URLQueryItem(name: "userID", value: userID)]
        return components.url
    }

    /// Best-effort realtime nudge to a teammate's inbox so they refetch invites
    /// immediately instead of waiting for the safety poll. Failures are ignored:
    /// www already holds the authoritative invite.
    private func notifyInboxRealtime(inviteeUserID: String) async {
        guard var components = URLComponents(string: relayURLString) else { return }
        components.path = "/v1/collaboration/inbox/notify"
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["inviteeUserId": inviteeUserID]
        )
        _ = try? await URLSession.shared.data(for: request)
    }

    private func connect(sessionID: String, code: String) async -> CollaborationRelayConnection? {
        await refreshPeerIdentityForCollaborationAdvertise()
        let normalizedCode = Self.normalizedSessionCode(from: code)
        if let existing = connectionsBySessionCode[normalizedCode] {
            guard await existing.joinAcknowledgement.wait(timeout: Self.joinAcknowledgementTimeout) else {
                connectionsBySessionCode.removeValue(forKey: normalizedCode)
                existing.disconnect()
                if sessionCode == normalizedCode {
                    sessionCode = nil
                }
                connectionLabel = CollaborationStrings.connectionFailed
                existing.connectionLabel = CollaborationStrings.connectionFailed
                await existing.session.markRelayUnavailable()
                return nil
            }
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
        guard await connection.joinAcknowledgement.wait(timeout: Self.joinAcknowledgementTimeout) else {
            connectionsBySessionCode.removeValue(forKey: normalizedCode)
            connection.disconnect()
            if sessionCode == normalizedCode {
                sessionCode = nil
            }
            connectionLabel = CollaborationStrings.connectionFailed
            connection.connectionLabel = CollaborationStrings.connectionFailed
            await nextSession.markRelayUnavailable()
            trackCollaboration(
                .connectionFailed,
                entrypoint: .system,
                result: .failed,
                properties: [
                    "operation": "join_acknowledgement",
                    "error_kind": "collaboration.join_failed",
                ],
                flush: true
            )
            return nil
        }
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
        if let grant = grant(forRoom: code) {
            components.queryItems?.append(URLQueryItem(name: "grant", value: grant))
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
        Task { @MainActor in
            await refreshPeerIdentityForCollaborationAdvertise()
            share(terminal: terminal, via: connection, entrypoint: .terminalHeaderButton)
        }
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
                // Order matters: open (pane) -> dimensions (grid lock) -> seed
                // (content). The seed replay is width-sensitive, so the viewer
                // must lock its mirror grid to our columns before processing
                // any screen content or its layout drifts from ours.
                try await send(.terminalOpen(terminalID: terminalID, descriptor: descriptor), via: connection)
                await sendHostedTerminalDimensionsNow(terminalID: terminalID, connection: connection, force: true)
                try await sendTerminalRenderGridSnapshotIfPossible(
                    terminalID: terminalID,
                    scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                    full: true,
                    requireLiveScrollbackBottom: false,
                    via: connection
                )
                // Retransmit the seed once shortly after share start. The
                // initial seed can fail to land visibly on the viewer (pane
                // still 0x0 when it applies, an older build dropping a frame
                // that raced pane creation, or a nil snapshot on our side);
                // by the retransmit the viewer pane exists and is laid out,
                // and the stateSeq overlap-trim makes a duplicate harmless.
                // This heals every viewer build, unlike viewer-side
                // re-requests which need the new client.
                scheduleHostedTerminalReseed(
                    terminalID: terminalID,
                    connection: connection,
                    delay: Self.shareStartSeedRetransmitDelay
                )
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
        if let ownerPeerID {
            mirroredTerminalOwnerPeerIDsByID[terminalID] = ownerPeerID
        }
        mirroredTerminalRenderGridPatchSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridSequencesByID.removeValue(forKey: terminalID)
        // A fresh share must re-establish the grid lock before any content
        // replays; the host sends open -> dimensions -> seed in that order.
        mirroredTerminalGridLockedIDs.remove(terminalID)
        pendingMirroredFramesAwaitingLockByID.removeValue(forKey: terminalID)
        mirroredGridLockFlushTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalLockedGridByID.removeValue(forKey: terminalID)
        mirroredReseedRequestTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredContentAppliedUnlockedIDs.remove(terminalID)
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
        // Apply any render-grid seeds that raced ahead of this open frame,
        // then watchdog the full seed: if none lands shortly, ask the host
        // to resend it instead of sitting on a black pane.
        if let pending = pendingMirroredRenderGridFramesByID.removeValue(forKey: terminalID) {
            for frame in pending {
                handleRemoteTerminalRenderGrid(terminalID: terminalID, frame: frame)
            }
        }
        scheduleMirroredRenderGridSeedRequestIfNeeded(terminalID: terminalID, connection: connection)
    }

    /// Requests a fresh full render-grid seed from the host when the mirror
    /// pane exists but no full seed has been applied after a grace period.
    /// Covers every known dropped-seed case: the relay's 1 MiB cap eating the
    /// frame, the host surface not being live when the share started, and a
    /// seed that raced pane registration on a connection that then went idle.
    private func scheduleMirroredRenderGridSeedRequestIfNeeded(
        terminalID: String,
        connection: CollaborationRelayConnection
    ) {
        mirroredRenderGridSeedRequestTasksByID[terminalID]?.cancel()
        mirroredRenderGridSeedRequestTasksByID[terminalID] = Task { @MainActor [weak self] in
            for _ in 0..<Self.mirroredRenderGridSeedRequestAttempts {
                try? await Task.sleep(for: Self.mirroredRenderGridSeedRequestDelay)
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.mirroredTerminalsByID[terminalID]?.panel != nil else { return }
                // A full seed has been applied; nothing to request.
                if self.mirroredTerminalRenderGridSequencesByID[terminalID] != nil { break }
                let recipients = self.terminalOwnerParticipantIDsByID[terminalID].map { [$0] }
                try? await self.send(CollaborationTerminalRenderGridRequestWire(
                    type: "terminal.render_grid.request",
                    terminalID: terminalID,
                    fromPeerID: self.peerIdentity.peerID,
                    recipientParticipantIDs: recipients
                ), via: connection)
            }
            self?.mirroredRenderGridSeedRequestTasksByID.removeValue(forKey: terminalID)
        }
    }

    private func handleRemoteTerminalOutput(
        terminalID: String,
        sequence: UInt64,
        data: Data,
        caretPeerID: String?,
        connection: CollaborationRelayConnection
    ) {
        guard mirroredTerminalsByID[terminalID]?.panel != nil else { return }
        guard mirroredTerminalGridLockedIDs.contains(terminalID) else {
            bufferMirroredFrameAwaitingLock(
                .output(sequence: sequence, data: data, caretPeerID: caretPeerID, connection: connection),
                terminalID: terminalID
            )
            return
        }
        applyRemoteTerminalOutput(
            terminalID: terminalID,
            sequence: sequence,
            data: data,
            caretPeerID: caretPeerID,
            connection: connection
        )
    }

    private func applyRemoteTerminalOutput(
        terminalID: String,
        sequence: UInt64,
        data: Data,
        caretPeerID: String?,
        connection: CollaborationRelayConnection
    ) {
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        if Self.echoTimingEnabled {
            let now = ProcessInfo.processInfo.systemUptime
            let last = echoLastApplyAtByID[terminalID]
            echoLastApplyAtByID[terminalID] = now
            let deltaMillis = last.map { String(format: "%.1f", (now - $0) * 1000.0) } ?? "-"
            Self.echoLog(
                "viewer-apply terminal=\(terminalID.prefix(8)) bytes=\(data.count) " +
                "dt=\(deltaMillis) t=\(Self.echoTimestampMillis())"
            )
        }
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
        // Keep the host cursor visible in a clipped mirror viewport.
        panel.surface.hostedView.syncMirrorViewportFollow()
        if let peer = peerVisibleToThisClient(caretPeerID, in: connection) {
            panel.surface.hostedView.showTerminalCollaboratorCaret(
                peerID: peer.peerID,
                displayName: peer.displayName,
                colorHex: peer.color
            )
        }
    }

    private func handleRemoteTerminalRenderGrid(terminalID: String, frame: MobileTerminalRenderGridFrame) {
        guard mirroredTerminalsByID[terminalID]?.panel != nil else {
            // The one-shot seed can race ahead of `terminal.open` registering
            // the mirror pane. Dropping it here left the pane black until
            // unrelated host output arrived; buffer it and drain on open.
            var pending = pendingMirroredRenderGridFramesByID[terminalID] ?? []
            pending.append(frame)
            if pending.count > Self.pendingMirroredRenderGridFrameLimit {
                pending.removeFirst(pending.count - Self.pendingMirroredRenderGridFrameLimit)
            }
            pendingMirroredRenderGridFramesByID[terminalID] = pending
            Self.seedLog("seed-recv buffered-preopen terminal=\(terminalID.prefix(8)) full=\(frame.full)")
            return
        }
        guard mirroredTerminalGridLockedIDs.contains(terminalID) else {
            // A full seed carries the host's grid, so it can establish the
            // lock by itself -- no dependency on a separate
            // `terminal.dimensions` frame winning the race (or existing at
            // all on older hosts). Drain any earlier buffered frames first so
            // arrival order is preserved, then apply this seed.
            if frame.full, frame.columns > 0, frame.rows > 0 {
                Self.seedLog("seed-recv locks-grid terminal=\(terminalID.prefix(8)) grid=\(frame.columns)x\(frame.rows)")
                lockMirroredTerminalGrid(terminalID: terminalID, columns: frame.columns, rows: frame.rows)
                applyRemoteTerminalRenderGrid(terminalID: terminalID, frame: frame)
            } else {
                Self.seedLog("seed-recv buffered-lock terminal=\(terminalID.prefix(8)) full=\(frame.full)")
                bufferMirroredFrameAwaitingLock(.renderGrid(frame), terminalID: terminalID)
            }
            return
        }
        applyRemoteTerminalRenderGrid(terminalID: terminalID, frame: frame)
    }

    /// Records and applies the mirror grid lock, then opens the content gate
    /// (draining buffered frames in arrival order).
    private func lockMirroredTerminalGrid(terminalID: String, columns: Int, rows: Int) {
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        mirroredTerminalLockedGridByID[terminalID] = TerminalGridSize(columns: columns, rows: rows)
        panel.surface.applyLockedMirrorGrid(columns: columns, rows: rows)
        // Re-run pane layout now that the lock exists: viewport mode sizes
        // the surface view to the full host grid (larger than a small pane).
        _ = panel.surface.hostedView.reconcileGeometryNow()
        openMirroredGridLockGate(terminalID: terminalID, hasActualLock: true)
    }

    private func applyRemoteTerminalRenderGrid(terminalID: String, frame: MobileTerminalRenderGridFrame) {
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        if let patchSequence = mirroredTerminalRenderGridPatchSequencesByID[terminalID],
           frame.stateSeq < patchSequence {
            return
        }
        if frame.full, frame.columns > 0, frame.rows > 0 {
            // A full seed is authoritative for the host grid: re-lock if it
            // differs from what we recorded (covers reseeds after a host
            // resize racing the dims frame), and clear the unlocked-content
            // marker -- this repaint IS the resync.
            let seedGrid = TerminalGridSize(columns: frame.columns, rows: frame.rows)
            if mirroredTerminalLockedGridByID[terminalID] != seedGrid {
                mirroredTerminalLockedGridByID[terminalID] = seedGrid
                panel.surface.applyLockedMirrorGrid(columns: seedGrid.columns, rows: seedGrid.rows)
            }
            mirroredContentAppliedUnlockedIDs.remove(terminalID)
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
            Self.seedLog(
                "seed-applied terminal=\(terminalID.prefix(8)) grid=\(frame.columns)x\(frame.rows) " +
                "stateSeq=\(frame.stateSeq) rowsInFrame=\(frame.rowSpans.count) scrollback=\(frame.scrollbackRows)"
            )
        }
        // Keep the host cursor visible in a clipped mirror viewport.
        panel.surface.hostedView.syncMirrorViewportFollow()
    }

    private static func isMirrorInputReportingMode(_ mode: MobileTerminalRenderGridFrame.ModeSetting) -> Bool {
        guard !mode.ansi else { return false }
        switch mode.code {
        // 2026 (synchronized output) must never replay onto a mirror: a
        // replayed `?2026h` with no closing `l` would make the mirror's
        // renderer hold every subsequent paint, which reads as frozen/bursty
        // typing. Ghostty's render-grid export currently excludes 2026 at the
        // source (`renderGridModeIsExcluded`), so this is defense-in-depth
        // against hosts whose export does not.
        case 9, 1000, 1002, 1003, 1004, 1005, 1006, 1007, 1015, 1016, 2004, 2026, 2027:
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
        Self.echoLog(
            "host-input terminal=\(terminalID.prefix(8)) bytes=\(filteredData.count) " +
            "t=\(Self.echoTimestampMillis())"
        )
        // Write the viewer's bytes straight to the PTY. The viewer's mirror
        // surface is mode-synchronized to this host surface, so it already
        // encoded keystrokes (including Kitty keyboard-protocol sequences like
        // Cmd+Z and Option+Left) into exactly the bytes the running program
        // expects. Re-parsing them through the socket-input grammar would split a
        // leading `ESC` into an Escape keypress and leak the remainder as literal
        // text, so collaboration input must pass through verbatim.
        switch panel.sendCollaborationInputResult(filteredData) {
        case .sent:
            panel.surface.forceRefresh(reason: "collaboration.terminalInput")
        case .queued, .inputQueueFull, .surfaceUnavailable, .processExited:
            break
        }
    }

    #if DEBUG
    /// Test hook for ``filteredTerminalCollaborationInput(_:pendingPrefix:direction:terminalID:)``
    /// that runs a single buffer through the filter with a throwaway pending
    /// prefix.
    static func debugFilteredCollaborationInputForTesting(_ data: Data) -> Data? {
        var pending = Data()
        return filteredTerminalCollaborationInput(
            data,
            pendingPrefix: &pending,
            direction: "test",
            terminalID: "test"
        )
    }
    #endif

    private static func filteredTerminalCollaborationInput(
        _ data: Data,
        pendingPrefix: inout Data,
        direction: String,
        terminalID: String
    ) -> Data? {
        guard !data.isEmpty || !pendingPrefix.isEmpty else { return nil }
        #if DEBUG
        let originalPendingCount = pendingPrefix.count
        mosaicDebugLog(
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
                mosaicDebugLog(
                    "collab.terminal.input.buffer direction=\(direction) terminal=\(terminalID) " +
                    "prefix=\(debugByteSummary(pendingPrefix))"
                )
                #endif
                break
            } else if let reportLength = terminalGeneratedReportLength(bytes, from: index) {
                #if DEBUG
                let report = Data(bytes[index..<(index + reportLength)])
                mosaicDebugLog(
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
        mosaicDebugLog(
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
                scrolledToBottom: pointer.scrolledToBottom,
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
        Task {
            await sendHostedTerminalDimensionsNow(
                terminalID: terminalID,
                connection: connection,
                recipientParticipantIDs: recipientParticipantIDs,
                force: force
            )
        }
    }

    /// Awaitable variant of ``broadcastHostedTerminalDimensions``: the frame is
    /// on the wire when this returns. Seed paths use this to guarantee the
    /// grid lock reaches the viewer BEFORE any screen content. Byte replay is
    /// width-sensitive (e.g. zsh's partial-line `%` mark emits `$COLUMNS - 1`
    /// spaces), so content replayed on an unlocked mirror at a different width
    /// wraps differently and the two screens' rows drift apart permanently.
    private func sendHostedTerminalDimensionsNow(
        terminalID: String,
        connection: CollaborationRelayConnection,
        recipientParticipantIDs: [String]? = nil,
        force: Bool = false
    ) async {
        guard let panel = hostedTerminalsByID[terminalID]?.panel,
              let cells = panel.surface.gridCells(), cells.columns > 0, cells.rows > 0 else { return }
        let grid = TerminalGridSize(columns: cells.columns, rows: cells.rows)
        let previousGrid = hostedTerminalBroadcastGridByID[terminalID]
        if !force, previousGrid == grid { return }
        hostedTerminalBroadcastGridByID[terminalID] = grid
        let recipients = recipientParticipantIDs ?? recipientParticipantIDsForSending(
            terminalID: terminalID,
            connection: connection
        )
        try? await send(CollaborationTerminalDimensionsWire(
            type: "terminal.dimensions",
            terminalID: terminalID,
            columns: grid.columns,
            rows: grid.rows,
            recipientParticipantIDs: recipients
        ), via: connection)
        // An organic grid change (host window resize, fullscreen TUI toggle)
        // invalidates content already rendered on every mirror: it was laid
        // out for the old width and mirrors suppress reflow. Proactively
        // follow up with a fresh full seed so viewers repaint cleanly without
        // waiting for their own request round-trip. Forced sends are the
        // seed paths themselves (share start, late joiner, seed request),
        // which already send a seed; the first-ever broadcast has no viewers
        // with stale content.
        if !force, let previousGrid, previousGrid != grid {
            scheduleHostedTerminalReseed(terminalID: terminalID, connection: connection)
        }
    }

    /// Debounced host-side full reseed after the host's own grid changed (or
    /// a share-start retransmit), so a live window drag reseeds once at the
    /// final size instead of per intermediate grid step. A minimum interval
    /// between reseeds keeps grid flapping from streaming large seed frames
    /// back-to-back.
    private func scheduleHostedTerminalReseed(
        terminalID: String,
        connection: CollaborationRelayConnection,
        delay: Duration = CollaborationRuntime.hostedTerminalReseedDebounce
    ) {
        hostedTerminalReseedTasksByID[terminalID]?.cancel()
        hostedTerminalReseedTasksByID[terminalID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let lastReseedAt = self.hostedTerminalLastReseedAtByID[terminalID] ?? 0
            let remaining = Self.hostedTerminalReseedMinInterval - (now - lastReseedAt)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                if Task.isCancelled { return }
            }
            self.hostedTerminalReseedTasksByID.removeValue(forKey: terminalID)
            guard self.hostedTerminalsByID[terminalID]?.panel != nil else { return }
            self.hostedTerminalLastReseedAtByID[terminalID] = ProcessInfo.processInfo.systemUptime
            // Grid lock first (it may have changed again during the
            // debounce), then the width-sensitive content.
            await self.sendHostedTerminalDimensionsNow(
                terminalID: terminalID,
                connection: connection,
                force: true
            )
            try? await self.sendTerminalRenderGridSnapshotIfPossible(
                terminalID: terminalID,
                scrollbackLines: Self.terminalInitialRenderGridScrollbackLines,
                full: true,
                requireLiveScrollbackBottom: false,
                via: connection
            )
        }
    }

    private func handleRemoteTerminalDimensions(terminalID: String, columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        // Only mirrors lock their grid to the host; the host is authoritative.
        guard let panel = mirroredTerminalsByID[terminalID]?.panel else { return }
        let grid = TerminalGridSize(columns: columns, rows: rows)
        let previousGrid = mirroredTerminalLockedGridByID[terminalID]
        mirroredTerminalLockedGridByID[terminalID] = grid
        panel.surface.applyLockedMirrorGrid(columns: columns, rows: rows)
        // Re-run pane layout now that the lock (possibly a new grid) exists:
        // viewport mode sizes the surface view to the full host grid.
        _ = panel.surface.hostedView.reconcileGeometryNow()
        let contentAppliedUnlocked = mirroredContentAppliedUnlockedIDs.remove(terminalID) != nil
        openMirroredGridLockGate(terminalID: terminalID, hasActualLock: true)
        // A mid-session host grid change invalidates everything already on
        // the mirror: content was laid out for the old width, and mirrors
        // suppress reflow on resize, so replayed bytes cannot repair it.
        // Same when this is the FIRST lock but content already rendered at an
        // unverified width (the gate's fallback opened before any lock).
        // Ask the host for a fresh full seed (RIS + repaint). Debounced so a
        // live window drag asks once; skipped if the host's own proactive
        // reseed (the primary mechanism) lands during the debounce.
        let contentApplied = mirroredTerminalRenderGridSequencesByID[terminalID] != nil
            || mirroredTerminalRenderGridPatchSequencesByID[terminalID] != nil
        let gridChangedUnderContent = previousGrid != nil && previousGrid != grid && contentApplied
        if gridChangedUnderContent || contentAppliedUnlocked {
            scheduleMirroredReseedRequest(terminalID: terminalID)
        }
    }

    /// Debounced viewer->host full-seed re-request after the locked grid
    /// changed under already-rendered content. Safety net for hosts that do
    /// not proactively reseed on their own grid change.
    private func scheduleMirroredReseedRequest(terminalID: String) {
        mirroredReseedRequestTasksByID[terminalID]?.cancel()
        let fullSeedSequenceAtSchedule = mirroredTerminalRenderGridSequencesByID[terminalID]
        mirroredReseedRequestTasksByID[terminalID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.mirroredReseedRequestDebounce)
            guard !Task.isCancelled, let self else { return }
            self.mirroredReseedRequestTasksByID.removeValue(forKey: terminalID)
            guard self.mirroredTerminalsByID[terminalID]?.panel != nil else { return }
            // A fresh full seed already arrived (the host reseeds
            // proactively); no need to request another.
            guard self.mirroredTerminalRenderGridSequencesByID[terminalID] == fullSeedSequenceAtSchedule else {
                return
            }
            guard let connection = self.connection(forTerminalID: terminalID) else { return }
            let recipients = self.terminalOwnerParticipantIDsByID[terminalID].map { [$0] }
            try? await self.send(CollaborationTerminalRenderGridRequestWire(
                type: "terminal.render_grid.request",
                terminalID: terminalID,
                fromPeerID: self.peerIdentity.peerID,
                recipientParticipantIDs: recipients
            ), via: connection)
        }
    }

    /// Marks the mirror grid as locked and replays, in arrival order, any
    /// seed/output frames that were held back waiting for the lock.
    ///
    /// - Parameter hasActualLock: `true` when a real grid lock (dims frame or
    ///   a full seed's own grid) triggered the open; `false` for the fallback
    ///   timer / overflow, which record the terminal as having rendered
    ///   content at an unverified width so a late-arriving lock can resync.
    private func openMirroredGridLockGate(terminalID: String, hasActualLock: Bool) {
        mirroredGridLockFlushTasksByID.removeValue(forKey: terminalID)?.cancel()
        let isNewlyLocked = mirroredTerminalGridLockedIDs.insert(terminalID).inserted
        if !hasActualLock, isNewlyLocked {
            mirroredContentAppliedUnlockedIDs.insert(terminalID)
        }
        guard isNewlyLocked || pendingMirroredFramesAwaitingLockByID[terminalID] != nil else { return }
        guard let pending = pendingMirroredFramesAwaitingLockByID.removeValue(forKey: terminalID) else { return }
        for frame in pending {
            switch frame {
            case .renderGrid(let gridFrame):
                applyRemoteTerminalRenderGrid(terminalID: terminalID, frame: gridFrame)
            case .output(let sequence, let data, let caretPeerID, let connection):
                applyRemoteTerminalOutput(
                    terminalID: terminalID,
                    sequence: sequence,
                    data: data,
                    caretPeerID: caretPeerID,
                    connection: connection
                )
            }
        }
    }

    private func bufferMirroredFrameAwaitingLock(
        _ frame: PendingMirroredTerminalFrame,
        terminalID: String
    ) {
        var pending = pendingMirroredFramesAwaitingLockByID[terminalID] ?? []
        pending.append(frame)
        pendingMirroredFramesAwaitingLockByID[terminalID] = pending
        // Output bytes must never be dropped (that corrupts the VT stream),
        // so an overflowing buffer opens the gate instead of trimming.
        if pending.count >= Self.pendingMirroredFramesAwaitingLockLimit {
            openMirroredGridLockGate(terminalID: terminalID, hasActualLock: false)
            return
        }
        guard mirroredGridLockFlushTasksByID[terminalID] == nil else { return }
        mirroredGridLockFlushTasksByID[terminalID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.mirroredGridLockFlushDelay)
            guard !Task.isCancelled, let self else { return }
            self.mirroredGridLockFlushTasksByID.removeValue(forKey: terminalID)
            self.openMirroredGridLockGate(terminalID: terminalID, hasActualLock: false)
        }
    }

    private func handleRemoteTerminalClose(terminalID: String) {
        syncTerminalTabPresentation(terminalID: terminalID, ownerSnapshot: nil)
        mirroredTerminalsByID.removeValue(forKey: terminalID)
        hostedTerminalsByID.removeValue(forKey: terminalID)
        removeTerminalSurfaceMappings(for: terminalID)
        hostedTerminalOutputSequencesByID.removeValue(forKey: terminalID)
        hostedTerminalOutputCaretSuppressionsByID.removeValue(forKey: terminalID)
        hostedTerminalBroadcastGridByID.removeValue(forKey: terminalID)
        hostedTerminalDimensionsProbedAtByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridPatchSequencesByID.removeValue(forKey: terminalID)
        mirroredTerminalRenderGridSequencesByID.removeValue(forKey: terminalID)
        pendingMirroredRenderGridFramesByID.removeValue(forKey: terminalID)
        echoLastApplyAtByID.removeValue(forKey: terminalID)
        mirroredRenderGridSeedRequestTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalGridLockedIDs.remove(terminalID)
        pendingMirroredFramesAwaitingLockByID.removeValue(forKey: terminalID)
        mirroredGridLockFlushTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredTerminalLockedGridByID.removeValue(forKey: terminalID)
        mirroredReseedRequestTasksByID.removeValue(forKey: terminalID)?.cancel()
        mirroredContentAppliedUnlockedIDs.remove(terminalID)
        hostedTerminalReseedTasksByID.removeValue(forKey: terminalID)?.cancel()
        hostedTerminalLastReseedAtByID.removeValue(forKey: terminalID)
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
            connection.joinAcknowledgement.fail()
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
            // Re-arm the socket read BEFORE processing the frame. Processing
            // can be heavy (terminal.output replays PTY bytes through Ghostty
            // on the main actor), and gating the next read on it made
            // latency-sensitive collaborator pointer frames arrive in uneven
            // bursts (visible as cursor stutter).
            receiveNextMessage(for: connection)

            // Fast path: collaborator pointer frames are tiny and
            // latest-position-wins, so apply them immediately instead of
            // queueing them behind earlier heavy frames in the ordered chain.
            // A pointer that references not-yet-opened terminals or unknown
            // peers is dropped harmlessly by the handler's guards.
            if applyTerminalPointerFastPath(data, connection: connection) {
                return
            }
            // Fast path: latency-critical terminal echo. When the ordered chain
            // is idle (nothing earlier is pending) and the mirror grid is
            // already locked, apply `terminal.output` inline instead of paying a
            // per-keystroke main-actor task hop. Ordering is preserved because
            // any in-flight chain work forces this and later frames back onto
            // the chain (the `pendingOrderedFrameCount == 0` gate).
            if applyTerminalOutputFastPath(data, connection: connection) {
                return
            }
            enqueueOrderedFrameProcessing(data, connection: connection)
        }
    }

    /// Applies a `terminal.pointer` frame synchronously if `data` is one.
    /// Returns `false` (without side effects) for every other frame type.
    ///
    /// The byte-token prescan avoids paying a full JSON parse on the hot
    /// output path just to discover a frame is not a pointer: only frames
    /// small enough to be a pointer and containing the quoted type token are
    /// decoded. False positives fall through to the decode + type check.
    private func applyTerminalPointerFastPath(
        _ data: Data,
        connection: CollaborationRelayConnection
    ) -> Bool {
        guard data.count <= Self.terminalPointerFastPathMaxBytes,
              data.range(of: Self.terminalPointerTypeToken) != nil,
              let pointer = try? decoder.decode(CollaborationTerminalPointerWire.self, from: data),
              pointer.type == "terminal.pointer" else {
            return false
        }
        handleRemoteTerminalPointer(pointer, connection: connection)
        return true
    }

    private static let terminalPointerTypeToken = Data("\"terminal.pointer\"".utf8)
    private static let terminalPointerFastPathMaxBytes = 2048

    /// Applies a `terminal.output` frame synchronously if `data` is one and it
    /// is safe to do so without reordering. Returns `false` (without side
    /// effects) otherwise, so the caller falls back to the ordered chain.
    ///
    /// Safe-to-inline requires: the ordered chain is idle
    /// (`pendingOrderedFrameCount == 0`, so no earlier open/seed/output is
    /// pending) and the mirror grid is already locked (live steady-state
    /// output; unlocked frames need the chain's buffer-until-lock handling).
    /// A byte-token prescan avoids a full JSON parse on frames that are not
    /// output; the size cap keeps the scan off large bursts, which are not
    /// keystroke-latency-sensitive and can take the ordered path.
    private func applyTerminalOutputFastPath(
        _ data: Data,
        connection: CollaborationRelayConnection
    ) -> Bool {
        guard connection.pendingOrderedFrameCount == 0,
              data.count <= Self.terminalOutputFastPathMaxBytes,
              data.range(of: Self.terminalOutputTypeToken) != nil,
              let output = try? decoder.decode(CollaborationTerminalOutputWire.self, from: data),
              output.type == "terminal.output",
              mirroredTerminalGridLockedIDs.contains(output.terminalID),
              let bytes = Data(base64Encoded: output.dataBase64) else {
            return false
        }
        // Field is named `via=` (not `path=`): the debug event log redacts
        // values keyed `path` as potential file paths, which hid this marker.
        Self.echoLog(
            "viewer-recv via=fast terminal=\(output.terminalID.prefix(8)) bytes=\(bytes.count) " +
            "t=\(Self.echoTimestampMillis())"
        )
        handleRemoteTerminalOutput(
            terminalID: output.terminalID,
            sequence: output.sequence,
            data: bytes,
            caretPeerID: output.caretPeerID,
            connection: connection
        )
        return true
    }

    private static let terminalOutputTypeToken = Data("\"terminal.output\"".utf8)
    private static let terminalOutputFastPathMaxBytes = 16384

    /// Appends a frame to the connection's strictly-ordered processing chain.
    /// Ordering matters for everything except pointers (e.g. terminal.open
    /// must register the mirror pane before terminal.render_grid seeds it),
    /// but processing must not block the socket read loop.
    private func enqueueOrderedFrameProcessing(
        _ data: Data,
        connection: CollaborationRelayConnection
    ) {
        let previous = connection.frameProcessingTask
        connection.pendingOrderedFrameCount += 1
        connection.frameProcessingTask = Task { @MainActor [weak self] in
            await previous?.value
            defer { connection.pendingOrderedFrameCount -= 1 }
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.handleFrameData(data, connection: connection)
            } catch {
                self.lastErrorMessage = error.localizedDescription
                if !connection.joinAcknowledgement.isResolved {
                    connection.joinAcknowledgement.fail()
                }
            }
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
            connection.joinAcknowledgement.succeed()
            refreshPeerSummaries(for: connection)
            trackCollaborationLayoutSnapshot(reason: "participant_joined", sessionCode: connection.sessionCode)
            await pruneStaleAgentRooms()
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
                await pruneStaleAgentRooms()
            }
        case "peer.update":
            let peer = try decoder.decode(CollaborationPeerUpdateWire.self, from: data).peer
            if peer.peerID != peerIdentity.peerID {
                connection.peersByID[peer.peerID] = peer
                refreshTerminalOwnerSnapshots(for: peer, in: connection)
                refreshPeerSummaries(for: connection)
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
                Self.echoLog(
                    "viewer-recv via=chain terminal=\(output.terminalID.prefix(8)) bytes=\(bytes.count) " +
                    "pending=\(connection.pendingOrderedFrameCount) t=\(Self.echoTimestampMillis())"
                )
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
        case "terminal.render_grid.request":
            let request = try decoder.decode(CollaborationTerminalRenderGridRequestWire.self, from: data)
            handleTerminalRenderGridRequest(request, connection: connection)
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
            await applyRemoteAgentRoomMembership(room: room, connection: connection)
        case "agent.room.snapshot":
            let wire = try decoder.decode(CollaborationAgentRoomSnapshotWire.self, from: data)
            await agentRoomStore.apply(snapshot: wire.room)
            cacheAgentRoom(wire.room)
            latestAgentRoomID = wire.room.id
            await applyRemoteAgentRoomMembership(room: wire.room, connection: connection)
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
        // stateSeq MUST live in the collaboration output-stream domain, which
        // numbers bytes from 0 at share start. The byte tee's counter (all PTY
        // bytes since surface creation, when mobile pairing is active) is a
        // DIFFERENT domain: stamping a seed with it made the viewer's overlap
        // trim (`endSequence > renderGridSequence`) silently swallow the first
        // post-share output -- on a fresh terminal, exactly the prompt drawn
        // moments after the snapshot.
        let stateSeq = hostedTerminalOutputSequencesByID[terminalID] ?? 0
        let recipients = recipientParticipantIDs ?? recipientParticipantIDsForSending(
            terminalID: terminalID,
            connection: connection
        )
        // Encode before sending and shrink scrollback until the frame fits
        // under the relay's message-size cap; an oversized seed is silently
        // dropped by the relay, leaving viewers with a black mirror pane.
        let payload = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: scrollbackLines
        ) { lines in
            guard let snapshot = panel.surface.mobileRenderGridFrame(
                stateSeq: stateSeq,
                full: full,
                scrollbackLines: lines
            ) else { return nil }
            let frame = terminalRenderGridFrameWithResolvedDefaults(snapshot.frame)
            return try? encoder.encode(CollaborationTerminalRenderGridWire(
                type: "terminal.render_grid",
                terminalID: terminalID,
                frame: frame,
                recipientParticipantIDs: recipients
            ))
        }
        guard let payload else {
            Self.seedLog("seed-skip terminal=\(terminalID.prefix(8)) reason=nil-snapshot stateSeq=\(stateSeq)")
            return
        }
        Self.seedLog(
            "seed-send terminal=\(terminalID.prefix(8)) bytes=\(payload.count) full=\(full) " +
            "stateSeq=\(stateSeq) recipients=\(recipients?.count.description ?? "all")"
        )
        try await send(encodedFrame: payload, via: connection)
    }

    /// Host side of the viewer's seed re-request: resend the full render-grid
    /// seed (and the grid lock) to the requesting participant only.
    private func handleTerminalRenderGridRequest(
        _ request: CollaborationTerminalRenderGridRequestWire,
        connection: CollaborationRelayConnection
    ) {
        let terminalID = request.terminalID
        guard hostedTerminalsByID[terminalID]?.panel != nil else { return }
        guard let requesterParticipantID = participantID(for: request.fromPeerID, in: connection) else { return }
        guard selectedRecipientParticipantIDs(for: terminalID, connection: connection)
            .contains(requesterParticipantID) else { return }
        let recipients = [requesterParticipantID]
        Task {
            // Re-lock the mirror grid FIRST: a viewer asking for a reseed may
            // also have missed the initial dimensions frame, and the seed
            // replay is width-sensitive, so the lock must land before content.
            await sendHostedTerminalDimensionsNow(
                terminalID: terminalID,
                connection: connection,
                recipientParticipantIDs: recipients,
                force: true
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
                // Late joiners must receive the host grid BEFORE the seed so
                // their mirror locks to the same columns/rows (and scales its
                // font to fit) before any width-sensitive content replays. The
                // periodic per-output broadcast is de-duped against the last
                // sent grid, so force a targeted send to this new recipient.
                await sendHostedTerminalDimensionsNow(
                    terminalID: terminalID,
                    connection: connection,
                    recipientParticipantIDs: recipients,
                    force: true
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

    private static func shouldSendTerminalRenderGridSnapshot(for panel: TerminalPanel) -> Bool {
        panel.surface.hostedView.isAtLiveScrollbackBottom
    }

    private func send(_ frame: CollaborationRelayFrame) async throws {
        // Agent-room membership/ledger frames are not tied to one session. A wired
        // room can bridge a mirrored terminal whose owning peer is reachable only
        // over the connection that carries the mirror, which may be a different
        // relay session than `activeConnection`. Fan these out to every connection
        // that hosts a wired peer (plus the active session) so a cross-peer wire
        // actually reaches the host. Non-room frames keep the single active path.
        switch frame {
        case .agentRoomSnapshot, .agentRoomEvent:
            try await broadcastAgentRoomFrame(frame)
        default:
            guard let connection = activeConnection else { throw CollaborationRuntimeError.notConnected }
            try await send(frame, via: connection)
        }
    }

    private func broadcastAgentRoomFrame(_ frame: CollaborationRelayFrame) async throws {
        let room: ClaudeRoomSnapshot?
        switch frame {
        case .agentRoomSnapshot(let snapshot): room = snapshot
        case .agentRoomEvent(let event): room = agentRoomSnapshotsByID[event.roomID]
        default: room = nil
        }
        let memberPeerIDs = Set(room?.members.map(\.peerID) ?? [])
        let owningConnectionCodes = room.map { agentRoomWiredOwnerConnectionCodesByRoomID[$0.id] ?? [] } ?? []
        var didSend = false
        for (code, connection) in connectionsBySessionCode {
            let reachesWiredPeer = !memberPeerIDs.isEmpty
                && connection.peersByID.keys.contains { memberPeerIDs.contains($0) }
            // Always include the connection that carries a wired mirror, so the
            // host receives snapshots/events before it has joined the room.
            let carriesWiredMirror = owningConnectionCodes.contains(code)
            guard reachesWiredPeer || carriesWiredMirror || code == sessionCode else { continue }
            try? await send(frame, via: connection)
            didSend = true
        }
        guard didSend else { throw CollaborationRuntimeError.notConnected }
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

    private func send<T: Encodable & Sendable>(_ frame: T) async throws {
        guard let connection = activeConnection else { throw CollaborationRuntimeError.notConnected }
        try await send(frame, via: connection)
    }

    private func send<T: Encodable & Sendable>(_ frame: T, via connection: CollaborationRelayConnection) async throws {
        guard let webSocketTask = connection.webSocketTask else { throw CollaborationRuntimeError.notConnected }
        // Encode + write on the codec actor's executor, not the main actor, so
        // the render/keystroke path is never blocked by JSON encoding (or the
        // base64 pass for terminal output) or by awaiting the socket write.
        try await frameWriter.send(frame, over: webSocketTask)
    }

    private func send(encodedFrame data: Data, via connection: CollaborationRelayConnection) async throws {
        guard let webSocketTask = connection.webSocketTask else { throw CollaborationRuntimeError.notConnected }
        try await frameWriter.send(encoded: data, over: webSocketTask)
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

    private var agentRoomDisplayOrder: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: Self.agentRoomDisplayOrderDefaultsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.agentRoomDisplayOrderDefaultsKey)
        }
    }

    private func registerAgentRoomDisplayOrder(roomID: String) {
        var order = agentRoomDisplayOrder
        guard !order.contains(roomID) else { return }
        order.append(roomID)
        agentRoomDisplayOrder = order
    }

    private func removeAgentRoomDisplayOrder(roomID: String) {
        var order = agentRoomDisplayOrder
        order.removeAll { $0 == roomID }
        agentRoomDisplayOrder = order
    }

    /// Mirrors authoritative room membership into the per-surface maps that
    /// drive the header "Claude room" pill, so every locally connected surface
    /// shows the tag no matter which entrypoint (click, wire drag, header
    /// drop, CLI) mutated the room. Uses the shared pure reducer so the
    /// invariant is unit-tested in one place.
    private func reconcileAgentRoomMembership(with room: ClaudeRoomSnapshot) {
        // The reducer maps every member with a UUID surface id to local
        // membership. Since rooms now sync across peers, a snapshot can contain
        // members owned by remote peers (e.g. the viewer's own terminal seen from
        // the host, or a host surface seen from the viewer). Filter to members
        // this app instance may legitimately map before reducing, so a remote
        // member never pollutes `agentRoomIDsBySurfaceID` (which would show a
        // phantom pill and mark the whole room degraded via the hook check).
        let localRoom = locallyMappableRoom(from: room)
        let reconciled = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(
                roomIDsBySurfaceID: agentRoomIDsBySurfaceID,
                memberIDsBySurfaceID: agentRoomMemberIDsBySurfaceID
            ),
            with: localRoom
        )
        agentRoomIDsBySurfaceID = reconciled.roomIDsBySurfaceID
        agentRoomMemberIDsBySurfaceID = reconciled.memberIDsBySurfaceID
        // Reserve a stable display slot for any room that now has a local
        // member (e.g. rooms rehydrated from disk on relaunch, which reconcile
        // without going through the connect path). Without this the room falls
        // to the end-of-list fallback number and can shift as others populate.
        if reconciled.roomIDsBySurfaceID.values.contains(room.id) {
            registerAgentRoomDisplayOrder(roomID: room.id)
        }
        agentRoomHeaderRevision &+= 1
        refreshAgentRoomHookHealth(room: localRoom)
    }

    /// Handles an incoming room snapshot/event from a peer: completes the join for
    /// any of this app's own hosted surfaces that a remote peer wired into the
    /// room (gated on the host having granted terminal-drive consent), then
    /// reconciles local membership so already-mapped surfaces refresh.
    private func applyRemoteAgentRoomMembership(
        room: ClaudeRoomSnapshot,
        connection: CollaborationRelayConnection
    ) async {
        var didComplete = false
        for member in room.members {
            // Match on the authoritative hosted-terminal mapping: the mirror's
            // terminalID encodes this host's real surface id, so a live share
            // resolves here even if the weak pane reference is momentarily nil.
            guard let surfaceUUID = UUID(uuidString: member.surfaceID),
                  let terminalID = hostedTerminalIDsBySurfaceID[surfaceUUID] else { continue }
            guard hostHasGrantedAgentRoomBridge(terminalID: terminalID, connection: connection) else {
                continue
            }
            if await completeHostAgentRoomJoin(member: member, surfaceUUID: surfaceUUID, roomID: room.id) {
                didComplete = true
            }
        }
        if didComplete, let enriched = await agentRoomStore.room(id: room.id) {
            cacheAgentRoom(enriched)
            agentRoomHeaderRevision &+= 1
            try? await send(.agentRoomSnapshot(enriched))
        }
        reconcileAgentRoomMembership(with: room)
    }

    /// Whether the host has authorized bridging its hosted terminal's Claude agent
    /// into a shared room. Reuses the existing terminal-drive consent: a host that
    /// has granted at least one collaborator input control for the terminal has
    /// opted into letting the room reach that agent. A read-only share stays inert.
    private func hostHasGrantedAgentRoomBridge(
        terminalID: String,
        connection: CollaborationRelayConnection
    ) -> Bool {
        !selectedRecipientParticipantIDs(for: terminalID, connection: connection).isEmpty
    }

    /// Maps a locally-hosted surface that a remote peer wired in into the room,
    /// attaches the host's live Claude session id, and backfills its transcript so
    /// the host agent's own hooks (`agent.room.consume`) begin delivering room
    /// context. Returns `true` when it changed state (so the caller rebroadcasts
    /// exactly once and steady-state receipts do not loop).
    @discardableResult
    private func completeHostAgentRoomJoin(
        member: ClaudeRoomMember,
        surfaceUUID: UUID,
        roomID: String
    ) async -> Bool {
        let surfaceID = surfaceUUID.uuidString
        let wasMapped = agentRoomIDsBySurfaceID[surfaceUUID] == roomID
        let hook = Self.claudeHookSessionRef(surfaceID: surfaceID)
        let needsSession = member.agentSessionID == nil && hook != nil
        guard !wasMapped || needsSession else { return false }

        agentRoomIDsBySurfaceID[surfaceUUID] = roomID
        agentRoomMemberIDsBySurfaceID[surfaceUUID] = member.id
        registerAgentRoomDisplayOrder(roomID: roomID)
        _ = await agentRoomStore.setDeliveryPolicy(roomID: roomID, policy: .semiLive)
        if needsSession, let hook {
            var updated = member
            updated.agentSessionID = hook.sessionID
            _ = await agentRoomStore.connect(member: updated, to: roomID)
        }
        let room = await agentRoomStore.room(id: roomID) ?? ClaudeRoomSnapshot(id: roomID)
        await ingestAgentRoomTranscriptFiles(roomID: roomID, members: room.members)
        let backfilled = await backfillAgentRoomLedgerFromTranscripts(
            roomID: roomID,
            joiningSurfaceID: surfaceID,
            room: room
        )
        cacheAgentRoom(backfilled)
        refreshAgentRoomHookHealth(room: backfilled)
        agentRoomHeaderRevision &+= 1
        return true
    }

    /// Whether a room member's peer is a currently-connected remote peer on any
    /// live relay connection. Our own peer is deliberately excluded so a room we
    /// no longer map locally can still be pruned.
    private func isAgentRoomMemberPeerConnected(_ peerID: String) -> Bool {
        guard peerID != peerIdentity.peerID else { return false }
        return connectionsBySessionCode.values.contains { $0.peersByID[peerID] != nil }
    }

    /// Whether a cached room is still relevant to this machine. Relevant rooms
    /// are kept; everything else is proliferation debris (orphaned ledgers from
    /// past sessions, foreign rooms whose peers all left) safe to GC locally.
    private func agentRoomIsLocallyRelevant(_ room: ClaudeRoomSnapshot) -> Bool {
        if room.id == latestAgentRoomID { return true }
        for member in room.members {
            guard let surfaceUUID = UUID(uuidString: member.surfaceID) else {
                if isAgentRoomMemberPeerConnected(member.peerID) { return true }
                continue
            }
            if agentRoomIDsBySurfaceID[surfaceUUID] != nil { return true }
            if hostedTerminalIDsBySurfaceID[surfaceUUID] != nil { return true }
            if terminalPanel(surfaceID: surfaceUUID) != nil { return true }
            if isAgentRoomMemberPeerConnected(member.peerID) { return true }
        }
        return false
    }

    /// Drops rooms that are no longer relevant to this machine to stop the room
    /// list from accumulating dead entries across sessions and relaunches (which
    /// otherwise buries the live wired room and can fork a new one each wire).
    private func pruneStaleAgentRooms() async {
        for room in Array(agentRoomSnapshotsByID.values) where !agentRoomIsLocallyRelevant(room) {
            _ = await agentRoomStore.removeRoom(id: room.id)
            agentRoomSnapshotsByID.removeValue(forKey: room.id)
            agentRoomWiredOwnerConnectionCodesByRoomID.removeValue(forKey: room.id)
            removeAgentRoomDisplayOrder(roomID: room.id)
            for member in room.members {
                if let surfaceUUID = UUID(uuidString: member.surfaceID) {
                    agentRoomIDsBySurfaceID.removeValue(forKey: surfaceUUID)
                    agentRoomMemberIDsBySurfaceID.removeValue(forKey: surfaceUUID)
                    agentRoomDegradedSurfaceIDs.remove(surfaceUUID)
                }
            }
        }
        agentRoomHeaderRevision &+= 1
    }

    /// Returns `room` filtered to the members this app instance may map into its
    /// local per-surface membership. Surface ids are globally unique, so a member
    /// is local only when its surface is a real terminal panel here. A locally
    /// *hosted* surface that a remote peer wired in is deliberately excluded from
    /// the blanket reconcile: it is mapped explicitly (and consent-gated) by
    /// `completeHostAgentRoomJoin`, never pre-mapped from an incoming snapshot.
    private func locallyMappableRoom(from room: ClaudeRoomSnapshot) -> ClaudeRoomSnapshot {
        var localRoom = room
        localRoom.members = room.members.filter { isLocallyMappableAgentRoomMember($0) }
        return localRoom
    }

    private func isLocallyMappableAgentRoomMember(_ member: ClaudeRoomMember) -> Bool {
        guard let surfaceUUID = UUID(uuidString: member.surfaceID),
              terminalPanel(surfaceID: surfaceUUID) != nil else { return false }
        // Already mapped locally: keep it so the reducer's idempotent refresh and
        // its "left the room" removal continue to work.
        if agentRoomIDsBySurfaceID[surfaceUUID] != nil { return true }
        // Not yet mapped and locally hosted: only the consent-gated host join path
        // may map it, so the blanket reconcile must not.
        if hostedTerminalIDsBySurfaceID[surfaceUUID] != nil { return false }
        return true
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
            withdrawTeammateInvites(forRoom: connection.sessionCode)
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

    /// Session-pill call to action for directory-sharing (team/enterprise)
    /// orgs, where sessions are an implementation detail behind sharing.
    static var sharePill: String {
        String(localized: "collaboration.action.sharePill", defaultValue: "Share")
    }

    static var shareWithTeammate: String {
        String(localized: "collaboration.action.shareWithTeammate", defaultValue: "Share with teammate")
    }

    static var addTeammate: String {
        String(localized: "collaboration.action.addTeammate", defaultValue: "Add teammate")
    }

    static var shareWithTeammateTitle: String {
        String(localized: "collaboration.directory.title", defaultValue: "Share with a teammate")
    }

    static var shareWithTeammateMessage: String {
        String(
            localized: "collaboration.directory.message",
            defaultValue: "Pick a teammate from your organization. They'll get this session in their incoming sessions."
        )
    }

    static var shareWithTeammateNoSession: String {
        String(
            localized: "collaboration.directory.noSession",
            defaultValue: "Start a session before sharing it with a teammate."
        )
    }

    static var sharePreparing: String {
        String(
            localized: "collaboration.directory.preparing",
            defaultValue: "Preparing session…"
        )
    }

    static var directoryEmpty: String {
        String(
            localized: "collaboration.directory.empty",
            defaultValue: "No other teammates are available in your organization yet."
        )
    }

    static var shareButton: String {
        String(localized: "collaboration.directory.share", defaultValue: "Share")
    }

    static var cancelButton: String {
        String(localized: "collaboration.directory.cancel", defaultValue: "Cancel")
    }

    static var okButton: String {
        String(localized: "collaboration.directory.ok", defaultValue: "OK")
    }

    static var incomingSessionsTitle: String {
        String(localized: "collaboration.inbox.title", defaultValue: "Incoming sessions")
    }

    static var incomingSessionsEmpty: String {
        String(localized: "collaboration.inbox.empty", defaultValue: "No incoming sessions")
    }

    static var incomingSessionsPrompt: String {
        String(
            localized: "collaboration.inbox.prompt",
            defaultValue: "Pick a session shared with you to join."
        )
    }

    static func incomingSessionsButton(count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.inbox.button", defaultValue: "Incoming sessions (%lld)"),
            count
        )
    }

    static var incomingSessionJoin: String {
        String(localized: "collaboration.inbox.join", defaultValue: "Join")
    }

    static var incomingInviteAlertTitle: String {
        String(
            localized: "collaboration.inbox.alert.title",
            defaultValue: "Incoming session invite"
        )
    }

    static var incomingInviteAlertDismiss: String {
        String(localized: "collaboration.inbox.alert.dismiss", defaultValue: "Dismiss")
    }

    static func incomingSessionSubtitle(ownerName: String, orgName: String) -> String {
        String.localizedStringWithFormat(
            String(
                localized: "collaboration.inbox.subtitle",
                defaultValue: "Shared by %1$@ in %2$@"
            ),
            ownerName,
            orgName
        )
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

    /// Headline for an active session on directory-sharing plans, where the
    /// invite code is intentionally not the primary sharing mechanism.
    static var directorySessionActive: String {
        String(localized: "collaboration.session.directory.active", defaultValue: "Session active")
    }

    static func sessionPillLabel(code: String, peerSummary: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.session.pill.label", defaultValue: "Session %@ · %@"),
            code,
            peerSummary
        )
    }

    static func sessionParticipantsTitle(count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "collaboration.session.participants.title", defaultValue: "People in session (%lld)"),
            count
        )
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

    static var connectAgentRoom: String {
        String(localized: "collaboration.agentRoom.connect", defaultValue: "Link agent room")
    }

    static func agentRoomLabel(number: Int) -> String {
        String(
            format: String(localized: "collaboration.agentRoom.labelFormat", defaultValue: "Room %d"),
            number
        )
    }

    static var agentRoomDragHint: String {
        String(localized: "collaboration.agentRoom.dragHint", defaultValue: "Drag")
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

    static var sessionCreatedMessage: String {
        String(
            localized: "collaboration.created.message",
            defaultValue: "Share this session code with collaborators"
        )
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

/// Styles native AppKit alert buttons that use Mosaic's yellow accent background.
/// `NSAlert` default buttons do not reliably honor only `attributedTitle`, so set
/// the control tint as well as the attributed fallback.
@MainActor
func applyCollaborationRegularAlertButtonTitleStyle(_ button: NSButton) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = button.font?.pointSize ?? NSFont.systemFontSize
    let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
    button.font = font
    button.attributedTitle = NSAttributedString(
        string: button.title,
        attributes: [
            .paragraphStyle: paragraph,
            .font: font,
        ]
    )
}

@MainActor
func applyCollaborationAccentAlertButtonTitleStyle(_ button: NSButton, font: NSFont? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let resolvedFont = font ?? NSFont.systemFont(
        ofSize: button.font?.pointSize ?? NSFont.systemFontSize,
        weight: .regular
    )

    let title = NSAttributedString(
        string: button.title,
        attributes: [
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
            .font: resolvedFont,
        ]
    )
    button.font = resolvedFont
    button.contentTintColor = .black
    button.attributedTitle = title
    button.attributedAlternateTitle = title
    if let cell = button.cell as? NSButtonCell {
        cell.attributedTitle = title
        cell.attributedAlternateTitle = title
    }
}

private final class CollaborationDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CollaborationDialogBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
        layer?.borderWidth = 1
    }
}

/// A non-blocking, indeterminate progress sheet used while awaiting async work
/// that has no meaningful intermediate UI (e.g. waiting for a concurrently
/// created collaboration session to finish connecting before an invite is
/// sent). Unlike ``CollaborationMessagePanel`` it never runs a nested modal
/// loop, so the awaiting caller keeps making progress and the run loop can
/// service both the spinner animation and the work being awaited.
///
/// `present()` defers actually showing the window by a short grace period and
/// `dismiss()` cancels that pending show, so a fast-resolving await never
/// flashes a dialog for a single frame.
@MainActor
private final class CollaborationProgressPanel {
    private let window: NSPanel
    private let spinner = NSProgressIndicator()
    private weak var parentWindow: NSWindow?
    private var pendingShow: DispatchWorkItem?
    private var isVisible = false

    init(title: String) {
        let size = NSSize(width: 320, height: 168)
        window = CollaborationDialogPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let background = CollaborationDialogBackgroundView(frame: contentView.bounds)
        background.frame = contentView.bounds
        background.autoresizingMask = [.width, .height]
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spinner)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 16, weight: .regular)
        titleField.textColor = .labelColor
        titleField.alignment = .center
        stack.addArrangedSubview(titleField)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            spinner.widthAnchor.constraint(equalToConstant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    /// Schedule the sheet to appear after a short grace period. If ``dismiss()``
    /// runs first, the window is never shown.
    func present(afterDelay delay: TimeInterval = 0.15) {
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show() {
        guard !isVisible else { return }
        isVisible = true
        spinner.startAnimation(nil)
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            parentWindow = parent
            parent.beginSheet(window)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        pendingShow?.cancel()
        pendingShow = nil
        guard isVisible else { return }
        isVisible = false
        spinner.stopAnimation(nil)
        if let parentWindow {
            parentWindow.endSheet(window)
        }
        window.orderOut(nil)
    }
}

@MainActor
private final class CollaborationMessagePanel {
    private let window: NSPanel
    private var response: NSApplication.ModalResponse = .alertFirstButtonReturn
    private var actionBoxes: [ButtonActionBox] = []

    init(title: String, message: String, buttonTitle: String) {
        let size = NSSize(width: 420, height: 286)
        window = CollaborationDialogPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let background = CollaborationDialogBackgroundView(frame: contentView.bounds)
        background.frame = contentView.bounds
        background.autoresizingMask = [.width, .height]
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(24, after: iconView)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor
        stack.addArrangedSubview(titleField)
        stack.setCustomSpacing(12, after: titleField)

        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.font = .systemFont(ofSize: 16, weight: .regular)
        messageField.textColor = .labelColor
        messageField.maximumNumberOfLines = 0
        messageField.preferredMaxLayoutWidth = 364
        stack.addArrangedSubview(messageField)
        stack.setCustomSpacing(28, after: messageField)

        let button = makeButton(title: buttonTitle, keyEquivalent: "\r") { [weak self] in
            self?.finish(.alertFirstButtonReturn)
        }
        stylePrimaryButton(button)
        stack.addArrangedSubview(button)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            titleField.widthAnchor.constraint(equalToConstant: 364),
            messageField.widthAnchor.constraint(equalToConstant: 364),
            button.widthAnchor.constraint(equalToConstant: 364),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @discardableResult
    func run() -> NSApplication.ModalResponse {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            window.orderOut(nil)
            return response
        }

        parent.beginSheet(window)
        window.makeKey()
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return response
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        self.response = response
        NSApp.stopModal()
    }

    private func makeButton(
        title: String,
        keyEquivalent: String,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.cell = CollaborationCenteredButtonCell(textCell: title)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 16, weight: .regular)
        button.alignment = .center
        button.keyEquivalent = keyEquivalent
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionBox = ButtonActionBox(action)
        actionBoxes.append(actionBox)
        button.target = actionBox
        button.action = #selector(ButtonActionBox.invoke)
        return button
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: MosaicChromePalette.accentHex) ?? .controlAccentColor
        applyCollaborationAccentAlertButtonTitleStyle(
            button,
            font: NSFont.systemFont(ofSize: 16, weight: .regular)
        )
    }

    private final class CollaborationCenteredButtonCell: NSButtonCell {
        override func titleRect(forBounds rect: NSRect) -> NSRect {
            var titleRect = super.titleRect(forBounds: rect)
            let titleHeight = attributedTitle.size().height
            titleRect.origin.y = rect.origin.y + ((rect.height - titleHeight) / 2)
            titleRect.size.height = titleHeight
            return titleRect
        }
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

@MainActor
private final class CollaborationSignInRequiredPanel {
    private let window: NSPanel
    private var response: NSApplication.ModalResponse = .alertSecondButtonReturn
    private var actionBoxes: [ButtonActionBox] = []

    init() {
        let size = NSSize(width: 420, height: 230)
        window = CollaborationDialogPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let background = CollaborationDialogBackgroundView(frame: contentView.bounds)
        background.frame = contentView.bounds
        background.autoresizingMask = [.width, .height]
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)

        let titleField = NSTextField(labelWithString: CollaborationStrings.signInRequiredTitle)
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.alignment = .center
        stack.addArrangedSubview(titleField)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        let cancelButton = makeButton(title: CollaborationStrings.cancel, keyEquivalent: "\u{1b}") { [weak self] in
            self?.finish(.alertSecondButtonReturn)
        }
        let signInButton = makeButton(title: CollaborationStrings.signIn, keyEquivalent: "\r") { [weak self] in
            self?.finish(.alertFirstButtonReturn)
        }
        styleSecondaryButton(cancelButton)
        stylePrimaryButton(signInButton)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(signInButton)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 364),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            titleField.widthAnchor.constraint(equalToConstant: 364),
            cancelButton.widthAnchor.constraint(equalToConstant: 144),
            signInButton.widthAnchor.constraint(equalToConstant: 144),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),
            signInButton.heightAnchor.constraint(equalToConstant: 36),
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
        window.makeKey()
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return response
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        self.response = response
        NSApp.stopModal()
    }

    private func makeButton(
        title: String,
        keyEquivalent: String,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.cell = CollaborationCenteredButtonCell(textCell: title)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 16, weight: .regular)
        button.alignment = .center
        button.keyEquivalent = keyEquivalent
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionBox = ButtonActionBox(action)
        actionBoxes.append(actionBox)
        button.target = actionBox
        button.action = #selector(ButtonActionBox.invoke)
        return button
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: MosaicChromePalette.accentHex) ?? .controlAccentColor
        applyCollaborationAccentAlertButtonTitleStyle(
            button,
            font: NSFont.systemFont(ofSize: 16, weight: .regular)
        )
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: "#2D2D2D") ?? NSColor.controlColor.withAlphaComponent(0.40)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            ]
        )
    }

    private final class CollaborationCenteredButtonCell: NSButtonCell {
        override func titleRect(forBounds rect: NSRect) -> NSRect {
            var titleRect = super.titleRect(forBounds: rect)
            let titleHeight = attributedTitle.size().height
            titleRect.origin.y = rect.origin.y + ((rect.height - titleHeight) / 2)
            titleRect.size.height = titleHeight
            return titleRect
        }
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

@MainActor
private final class CollaborationJoinSessionPanel {
    private let window: NSPanel
    private var response: NSApplication.ModalResponse = .alertSecondButtonReturn
    private var code = ""
    private let entryView = CollaborationInviteCodeEntryView(
        accessibilityLabel: CollaborationStrings.sessionCodePlaceholder
    )
    private var actionBoxes: [ButtonActionBox] = []
    private static let contentWidth: CGFloat = 464

    init() {
        let size = NSSize(width: 520, height: 408)
        window = CollaborationDialogPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let background = CollaborationDialogBackgroundView(frame: contentView.bounds)
        background.frame = contentView.bounds
        background.autoresizingMask = [.width, .height]
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)

        let titleField = NSTextField(labelWithString: CollaborationStrings.joinSession)
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor
        stack.addArrangedSubview(titleField)
        stack.setCustomSpacing(18, after: titleField)

        let messageField = NSTextField(wrappingLabelWithString: CollaborationStrings.joinMessage)
        messageField.font = .systemFont(ofSize: 16, weight: .regular)
        messageField.textColor = .labelColor
        messageField.maximumNumberOfLines = 0
        messageField.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(messageField)
        stack.setCustomSpacing(32, after: messageField)

        let codeRow = NSStackView()
        codeRow.orientation = .horizontal
        codeRow.alignment = .centerY
        codeRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(codeRow)
        codeRow.addArrangedSubview(NSView())
        codeRow.addArrangedSubview(entryView)
        codeRow.addArrangedSubview(NSView())
        stack.setCustomSpacing(34, after: codeRow)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        let cancelButton = makeButton(title: CollaborationStrings.cancel, keyEquivalent: "\u{1b}") { [weak self] in
            self?.finish(.alertSecondButtonReturn)
        }
        let joinButton = makeButton(title: CollaborationStrings.joinSession, keyEquivalent: "\r") { [weak self] in
            self?.submitIfComplete()
        }
        styleSecondaryButton(cancelButton)
        stylePrimaryButton(joinButton)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(joinButton)

        entryView.onSubmit = { [weak self] in
            self?.submitIfComplete()
        }
        entryView.onCancel = { [weak self] in
            self?.finish(.alertSecondButtonReturn)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            titleField.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            messageField.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            codeRow.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            buttonRow.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 144),
            joinButton.widthAnchor.constraint(equalToConstant: 144),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),
            joinButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        stack.setCustomSpacing(34, after: iconView)
    }

    func run() -> String? {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(entryView)
            NSApp.runModal(for: window)
            window.orderOut(nil)
            return response == .alertFirstButtonReturn ? code : nil
        }

        parent.beginSheet(window)
        window.makeKey()
        window.makeFirstResponder(entryView)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return response == .alertFirstButtonReturn ? code : nil
    }

    private func submitIfComplete() {
        guard entryView.isComplete else { return }
        code = entryView.code
        finish(.alertFirstButtonReturn)
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        self.response = response
        NSApp.stopModal()
    }

    private func makeButton(
        title: String,
        keyEquivalent: String,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 16, weight: .regular)
        button.keyEquivalent = keyEquivalent
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionBox = ButtonActionBox(action)
        actionBoxes.append(actionBox)
        button.target = actionBox
        button.action = #selector(ButtonActionBox.invoke)
        return button
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: MosaicChromePalette.accentHex) ?? .controlAccentColor
        applyCollaborationAccentAlertButtonTitleStyle(
            button,
            font: NSFont.systemFont(ofSize: 16, weight: .regular)
        )
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: "#2D2D2D") ?? NSColor.controlColor.withAlphaComponent(0.40)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            ]
        )
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

@MainActor
private final class CollaborationSessionCreatedPanel {
    private let window: NSPanel
    private var response: NSApplication.ModalResponse = .alertSecondButtonReturn
    private var actionBoxes: [ButtonActionBox] = []

    init(code: String) {
        let size = NSSize(width: 420, height: 286)
        window = CollaborationDialogPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovableByWindowBackground = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let background = CollaborationDialogBackgroundView(frame: contentView.bounds)
        background.frame = contentView.bounds
        background.autoresizingMask = [.width, .height]
        contentView.addSubview(background)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.Name("AppIconLight")) ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(12, after: iconView)

        let titleField = NSTextField(labelWithString: CollaborationStrings.sessionCreatedTitle)
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor
        stack.addArrangedSubview(titleField)
        stack.setCustomSpacing(10, after: titleField)

        let messageField = NSTextField(wrappingLabelWithString: CollaborationStrings.sessionCreatedMessage)
        messageField.font = .systemFont(ofSize: 16, weight: .regular)
        messageField.textColor = .labelColor
        messageField.maximumNumberOfLines = 0
        messageField.preferredMaxLayoutWidth = 364
        stack.addArrangedSubview(messageField)
        stack.setCustomSpacing(14, after: messageField)

        let codeRow = NSStackView()
        codeRow.orientation = .horizontal
        codeRow.alignment = .centerY
        codeRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(codeRow)
        codeRow.addArrangedSubview(NSView())

        let codeField = NSTextField(labelWithString: code)
        codeField.font = .monospacedSystemFont(ofSize: 24, weight: .semibold)
        codeField.textColor = .labelColor
        codeField.alignment = .center
        codeField.isSelectable = true
        codeField.wantsLayer = true
        codeField.layer?.cornerRadius = 8
        codeField.layer?.cornerCurve = .continuous
        codeField.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        codeField.translatesAutoresizingMaskIntoConstraints = false
        codeRow.addArrangedSubview(codeField)
        codeRow.addArrangedSubview(NSView())
        stack.setCustomSpacing(22, after: codeRow)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        let doneButton = makeButton(title: CollaborationStrings.done, keyEquivalent: "\u{1b}") { [weak self] in
            self?.finish(.alertSecondButtonReturn)
        }
        let copyButton = makeButton(title: CollaborationStrings.copyCode, keyEquivalent: "\r") { [weak self] in
            self?.finish(.alertFirstButtonReturn)
        }
        styleSecondaryButton(doneButton)
        stylePrimaryButton(copyButton)
        buttonRow.addArrangedSubview(doneButton)
        buttonRow.addArrangedSubview(copyButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            titleField.widthAnchor.constraint(equalToConstant: 364),
            messageField.widthAnchor.constraint(equalToConstant: 364),
            codeRow.widthAnchor.constraint(equalToConstant: 364),
            codeField.heightAnchor.constraint(equalToConstant: 46),
            codeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            buttonRow.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 144),
            copyButton.widthAnchor.constraint(equalToConstant: 144),
            doneButton.heightAnchor.constraint(equalToConstant: 36),
            copyButton.heightAnchor.constraint(equalToConstant: 36),
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
        window.makeKey()
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return response
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        self.response = response
        NSApp.stopModal()
    }

    private func makeButton(
        title: String,
        keyEquivalent: String,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 16, weight: .regular)
        button.keyEquivalent = keyEquivalent
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionBox = ButtonActionBox(action)
        actionBoxes.append(actionBox)
        button.target = actionBox
        button.action = #selector(ButtonActionBox.invoke)
        return button
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: MosaicChromePalette.accentHex) ?? .controlAccentColor
        applyCollaborationAccentAlertButtonTitleStyle(
            button,
            font: NSFont.systemFont(ofSize: 16, weight: .regular)
        )
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelColor = NSColor(hex: "#2D2D2D") ?? NSColor.controlColor.withAlphaComponent(0.40)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            ]
        )
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
        createButton.bezelColor = NSColor(hex: MosaicChromePalette.accentHex) ?? .controlAccentColor
        applyCollaborationAccentAlertButtonTitleStyle(
            createButton,
            font: NSFont.systemFont(ofSize: 16, weight: .regular)
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
        button.font = .systemFont(ofSize: 16, weight: .regular)
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
                .mosaicFont(size: 10, weight: .semibold)
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
