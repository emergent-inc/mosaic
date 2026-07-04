import SwiftUI
import Foundation
import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxTestSupport
import CmuxCollaboration
import CmuxTerminal
import CmuxFoundation
import UniformTypeIdentifiers

/// View for rendering a terminal panel
struct TerminalPanelView: View {
    @ObservedObject var panel: TerminalPanel
    @AppStorage(NotificationPaneRingSettings.enabledKey)
    private var notificationPaneRingEnabled = NotificationPaneRingSettings.defaultEnabled
    @AppStorage(TerminalTextBoxInputSettings.maxLinesKey)
    private var textBoxMaxLines = TerminalTextBoxInputSettings.defaultMaxLines
    @State private var terminalFontSize = GhosttyConfig.load(globalFontMagnificationPercent: GlobalFontMagnification.storedPercent).fontSize
    @State private var isTerminalSessionPopoverPresented = false
    @State private var isTerminalRecipientPopoverPresented = false
    @State private var isTerminalSessionPillHovered = false
    @State private var isAgentRoomButtonHovered = false
    @State private var isAgentRoomWireDropTargeted = false
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let terminalAgentContext: String
    let onFocus: () -> Void
    let onResumeAgentHibernation: () -> Void
    let onAutoResumeAgentHibernation: () -> Void
    let onTriggerFlash: () -> Void

    var body: some View {
        if let hibernationState = panel.agentHibernationState {
            hibernationBody(hibernationState)
        } else {
            terminalBody
        }
    }

    @ViewBuilder
    private func hibernationBody(_ hibernationState: AgentHibernationPanelState) -> some View {
        if isVisibleInUI {
            Color(nsColor: appearance.contentBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("hibernated-resuming-\(panel.id.uuidString)")
                .onAppear {
                    onAutoResumeAgentHibernation()
                }
        } else {
            AgentHibernationPlaceholderView(
                state: hibernationState,
                appearance: appearance,
                onResume: onResumeAgentHibernation
            )
            .id("hibernated-\(panel.id.uuidString)")
            .onChange(of: isVisibleInUI) { _, visible in
                if visible {
                    onAutoResumeAgentHibernation()
                }
            }
        }
    }

    private var terminalBody: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()

            // Layering contract: terminal find UI is mounted in GhosttySurfaceScrollView (AppKit portal layer)
            // via `searchState`. Rendering `SurfaceSearchOverlay` in this SwiftUI container can hide it.
            GhosttyTerminalView(
                terminalSurface: panel.surface,
                paneId: paneId,
                isActive: isFocused,
                isVisibleInUI: isVisibleInUI,
                portalZPriority: portalPriority,
                showsInactiveOverlay: isSplit && !isFocused,
                showsUnreadNotificationRing: hasUnreadNotification && notificationPaneRingEnabled,
                inactiveOverlayColor: appearance.unfocusedOverlayNSColor,
                inactiveOverlayOpacity: appearance.unfocusedOverlayOpacity,
                searchState: panel.searchState,
                reattachToken: panel.viewReattachToken,
                onFocus: { _ in
                    panel.terminalDidBecomeFocused()
                    onFocus()
                },
                onTriggerFlash: onTriggerFlash
            )
            // Keep the NSViewRepresentable identity stable across bonsplit structural updates.
            // This prevents transient teardown/recreate that can momentarily detach the hosted terminal view.
            .id(panel.id)
            .background(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#if DEBUG
            .reportTerminalViewportGeometryForUITest(panel: panel)
#endif
            .layoutPriority(1)

            if panel.isTextBoxActive {
                TextBoxInputContainer(
                    text: $panel.textBoxContent,
                    attachments: $panel.textBoxAttachments,
                    surface: panel.surface,
                    terminalBackgroundColor: appearance.backgroundColor,
                    terminalForegroundColor: appearance.foregroundColor,
                    terminalFont: NSFont.monospacedSystemFont(
                        ofSize: terminalFontSize,
                        weight: .regular
                    ),
                    maxLines: TerminalTextBoxInputSettings.resolvedMaxLines(textBoxMaxLines),
                    terminalAgentContext: terminalAgentContext,
                    onFocusTextBox: {
                        panel.textBoxDidBecomeFocused()
                        onFocus()
                    },
                    onToggleFocus: {
                        _ = panel.focusTextBoxInputOrTerminal()
                    },
                    onEscape: {
                        panel.handleTextBoxEscape()
                    },
                    onTextViewCreated: { view in
                        panel.registerTextBoxInputView(view)
                    },
                    onTextViewMovedToWindow: { view in
                        panel.textBoxInputViewDidMoveToWindow(view)
                    },
                    onTextViewDismantled: { view in
                        panel.preserveTextBoxContentForUnmount(from: view)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyConfigDidReload)) { _ in
            terminalFontSize = GhosttyConfig.load(globalFontMagnificationPercent: GlobalFontMagnification.storedPercent).fontSize
        }
    }

    private var terminalHeader: some View {
        let state = CollaborationRuntime.shared.state(for: panel)
        let agentRoomState = CollaborationRuntime.shared.agentRoomState(for: panel)
        return HStack(spacing: 8) {
            CmuxSystemSymbolImage(systemName: panel.displayIcon ?? "terminal.fill", pointSize: 13)
                .foregroundStyle(.secondary)
                .frame(width: 13)
            Text(panel.displayTitle)
                .cmuxFont(size: 10, design: .monospaced)
                .foregroundStyle(Color(nsColor: appearance.foregroundColor).opacity(0.68))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            agentRoomStatusView(state: agentRoomState)
            terminalAgentRoomButton
            terminalSessionPill(state: state)
            if state.workspaceSessionCode != nil || state.isMirrored {
                terminalShareButton(state: state)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(isAgentRoomWireDropTargeted ? Color.blue.opacity(0.14) : Color.clear)
        // The pane drop target only covers the terminal content area, so wire drops
        // released over the header (including the link button itself — the natural
        // button-to-button gesture) must be accepted here; otherwise the drop
        // silently connects nothing and no room pill appears.
        .onDrop(
            of: [AgentRoomWireDragPayload.contentType],
            isTargeted: $isAgentRoomWireDropTargeted
        ) { providers in
            handleAgentRoomWireHeaderDrop(providers)
        }
    }

    private func handleAgentRoomWireHeaderDrop(_ providers: [NSItemProvider]) -> Bool {
        let typeIdentifier = AgentRoomWireDragPayload.contentType.identifier
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(typeIdentifier)
        }) else {
            return false
        }
        let targetSurfaceID = panel.id
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data,
                  let raw = String(data: data, encoding: .utf8),
                  let sourceUUID = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  sourceUUID != targetSurfaceID else {
                return
            }
            Task { @MainActor in
                CollaborationRuntime.shared.connectAgentRoomWire(
                    sourceSurfaceID: sourceUUID.uuidString,
                    targetSurfaceID: targetSurfaceID
                )
            }
        }
        return true
    }

    @ViewBuilder
    private func agentRoomStatusView(state: AgentRoomHeaderState) -> some View {
        if state.isConnected {
            HStack(spacing: 4) {
                CmuxSystemSymbolImage(
                    systemName: state.isDegraded ? "exclamationmark.triangle.fill" : "link",
                    pointSize: 9,
                    weight: .semibold
                )
                Text(state.label)
                    .cmuxFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(state.isDegraded ? Color.orange : Color.blue))
            .help(
                state.isDegraded
                    ? String(
                        localized: "collaboration.agentRoom.degradedHelp",
                        defaultValue: "An agent in this room has no active Claude hook session; shared context may not sync. Restart Claude in that pane to relink."
                    )
                    : String(
                        localized: "collaboration.agentRoom.connectedHelp",
                        defaultValue: "Wired agents share context through this room."
                    )
            )
            .accessibilityIdentifier("TerminalAgentRoomConnectedPill")
        }
    }

    private func terminalSessionPill(state: CollaborationTerminalHeaderState) -> some View {
        let label = terminalSessionPillLabel(state: state)
        let pillModel = CollaborationTerminalSessionPillModel(
            workspaceSessionCode: state.workspaceSessionCode,
            participantCount: CollaborationRuntime.shared.participantSnapshots(for: panel).count
        )
        let hoverColor = Color.orange
        let foregroundColor = Color.orange
        let backgroundColor = isTerminalSessionPillHovered
            ? hoverColor.opacity(0.14)
            : Color.primary.opacity(state.workspaceSessionCode == nil ? 0.06 : 0.10)
        let borderColor = isTerminalSessionPillHovered
            ? hoverColor.opacity(0.24)
            : Color.primary.opacity(state.workspaceSessionCode == nil ? 0.10 : 0.16)
        return TrackedButton("session_pill_open", action: {
#if DEBUG
            print("[PostHog] firing: session_pill_tapped")
#endif
            PostHogAnalytics.shared.capture("session_pill_tapped", properties: [
                "session_state": state.workspaceSessionCode == nil ? "no_session" : "active_session",
            ])
            if CollaborationRuntime.shared.ensureSignedInForCollaboration(continue: {
                isTerminalSessionPopoverPresented = true
            }) {
                isTerminalSessionPopoverPresented = true
            }
        }) {
            HStack(spacing: 5) {
                CmuxSystemSymbolImage(systemName: "person.2", pointSize: 10, weight: .semibold)
                    .accessibilityHidden(true)
                Text(pillModel.showsParticipantCount
                    ? String.localizedStringWithFormat("%d", pillModel.otherParticipantCount)
                    : label)
                    .cmuxFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(backgroundColor)
            }
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("TerminalCollaborationSessionPill")
        .onHover { hovering in
            isTerminalSessionPillHovered = hovering
        }
        .cmuxCursorOnHover(.pointingHand)
        .popover(isPresented: $isTerminalSessionPopoverPresented, arrowEdge: .bottom) {
            TerminalCollaborationSessionPopoverContent(
                sessionCode: state.workspaceSessionCode,
                isConnected: state.isWorkspaceSessionConnected,
                peerSummary: state.peerSummary,
                participants: CollaborationRuntime.shared.participantSnapshots(for: panel),
                onCreate: {
                    CollaborationRuntime.shared.createWorkspaceSession(for: panel)
                    isTerminalSessionPopoverPresented = false
                },
                onJoin: {
                    CollaborationRuntime.shared.joinWorkspaceSession(for: panel)
                    isTerminalSessionPopoverPresented = false
                },
                onCopyInviteCode: {
                    CollaborationRuntime.shared.copyWorkspaceSessionInviteCode(for: panel)
                    isTerminalSessionPopoverPresented = false
                },
                onLeave: {
                    CollaborationRuntime.shared.leaveWorkspaceSession(for: panel)
                    isTerminalSessionPopoverPresented = false
                }
            )
        }
    }

    private func terminalSessionPillLabel(state: CollaborationTerminalHeaderState) -> String {
        guard let sessionCode = state.workspaceSessionCode else {
            return CollaborationStrings.startSession
        }
        return CollaborationStrings.sessionPillLabel(code: sessionCode, peerSummary: state.peerSummary)
    }

    private func terminalShareButton(state: CollaborationTerminalHeaderState) -> some View {
        let label = terminalShareButtonLabel(state: state)
        let icon = terminalShareButtonIcon(state: state)
        // All states share the orange tint; the passive "Viewing" (mirrored) and "Sharing"
        // (hosted) states use a slightly lower-saturation orange, leaving the actionable
        // "Share" call-to-action at full saturation.
        let tint = (state.isMirrored || state.isHosted)
            ? Color(hue: 0.085, saturation: 0.62, brightness: 0.98)
            : Color.orange
        return TrackedButton("terminal_share", action: {
            // "Viewing" is a read-only presence indicator in a shared session:
            // pressing it must do nothing.
            guard !state.isMirrored else { return }
            if !CollaborationRuntime.shared.state(for: panel).isHosted {
                CollaborationRuntime.shared.setSharing(true, for: panel)
            }
            isTerminalRecipientPopoverPresented = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .cmuxFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(tint.opacity(state.isHosted ? 0.14 : 0.08))
            }
            .overlay {
                Capsule()
                    .stroke(tint.opacity(state.isHosted ? 0.24 : 0.14), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("TerminalCollaborationShareButton")
        .cmuxCursorOnHover(.pointingHand)
        .popover(isPresented: $isTerminalRecipientPopoverPresented, arrowEdge: .bottom) {
            TerminalCollaborationRecipientPopoverContent(
                recipients: CollaborationRuntime.shared.recipientSnapshots(for: panel),
                onCopyInviteCode: {
                    CollaborationRuntime.shared.copyTerminalSessionInviteCode(for: panel)
                    isTerminalRecipientPopoverPresented = false
                },
                onSelectionChanged: { selectedIDs in
                    CollaborationRuntime.shared.applyRecipientSelection(selectedIDs, for: panel)
                },
                onStopSharing: {
                    CollaborationRuntime.shared.setSharing(false, for: panel)
                    isTerminalRecipientPopoverPresented = false
                }
            )
        }
    }

    private func terminalShareButtonIcon(state: CollaborationTerminalHeaderState) -> String {
        if state.isMirrored {
            return "eye"                 // Viewing: passive presence indicator
        }
        guard state.isHosted else {
            return "arrow.up"            // Share: send/publish this terminal
        }
        return "stop.circle.fill"       // Sharing: filled stop-square-in-a-circle indicator
    }

    private func terminalShareButtonLabel(state: CollaborationTerminalHeaderState) -> String {
        if state.isMirrored {
            return CollaborationStrings.viewingRemoteTerminal
        }
        guard state.isHosted else {
            return CollaborationStrings.share
        }
        return CollaborationStrings.sharingTerminal
    }

    private var terminalAgentRoomButton: some View {
        let state = CollaborationRuntime.shared.agentRoomState(for: panel)
        return PanelHeaderIconButton(
            systemName: state.isConnected ? "link.circle.fill" : "link.circle",
            label: state.label,
            isDisabled: false,
            hoverCursor: .openHand,
            hoverBackgroundColor: .blue,
            hoverForegroundColor: .blue,
            isHoverForced: isAgentRoomButtonHovered,
            action: {
                CollaborationRuntime.shared.connectAgentRoomFromHeader(panel: panel)
            }
        )
        .foregroundColor(state.isConnected ? .blue : .secondary)
        .accessibilityIdentifier("TerminalAgentRoomButton")
        .background(AgentRoomWireAnchorRepresentable(surfaceID: panel.id))
        .overlay {
            AgentRoomWireDragSourceRepresentable(
                panel: panel,
                onHoverChanged: { isAgentRoomButtonHovered = $0 }
            ) {
                CollaborationRuntime.shared.connectAgentRoomFromHeader(panel: panel)
            }
        }
    }
}

private struct TerminalCollaborationSessionPopoverContent: View {
    let sessionCode: String?
    let isConnected: Bool
    let peerSummary: String
    let participants: [CollaborationWorkspaceParticipantSnapshot]
    let onCreate: () -> Void
    let onJoin: () -> Void
    let onCopyInviteCode: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("AppIconLight", bundle: .main)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                Text(CollaborationStrings.sessionPopoverTitle)
                    .cmuxFont(size: 12, weight: .semibold)
            }

            if let sessionCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CollaborationStrings.sessionCodeLabel(code: sessionCode))
                        .cmuxFont(size: 11, weight: .semibold)
                        .textSelection(.enabled)
                    Text(isConnected ? CollaborationStrings.sessionConnectedDetail(peerSummary: peerSummary) : CollaborationStrings.sessionJoinedDetail)
                        .cmuxFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !participants.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CollaborationStrings.sessionParticipantsTitle)
                            .cmuxFont(size: 11, weight: .semibold)
                        ForEach(participants) { participant in
                            HStack(spacing: 7) {
                                CollaborationParticipantAvatarImage(
                                    participant: participant,
                                    size: 18,
                                    fallbackFontSize: 9,
                                    fallbackFontWeight: .bold,
                                    fallbackUsesRoundedDesign: false
                                )
                                Text(participant.displayName)
                                    .cmuxFont(size: 11)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Ends only *your* participation: stops sharing every terminal you host in
                // this session and disconnects you. Other people's shared terminals are
                // untouched. The pill reverts to "Start session" once this clears the binding.
                TrackedButton("session_end", CollaborationStrings.endSession) {
                    onLeave()
                }
                .buttonStyle(.mosaicSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TrackedButton("session_create", CollaborationStrings.createSession) {
                        onCreate()
                    }
                    .buttonStyle(.mosaicAccent)
                    .keyboardShortcut(.defaultAction)

                    TrackedButton("session_join", CollaborationStrings.joinSession) {
                        onJoin()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}

private struct TerminalCollaborationRecipientPopoverContent: View {
    let recipients: [CollaborationTerminalRecipientSnapshot]
    let onCopyInviteCode: () -> Void
    let onSelectionChanged: (Set<String>) -> Void
    let onStopSharing: () -> Void
    @State private var selectedParticipantIDs: Set<String>

    init(
        recipients: [CollaborationTerminalRecipientSnapshot],
        onCopyInviteCode: @escaping () -> Void,
        onSelectionChanged: @escaping (Set<String>) -> Void,
        onStopSharing: @escaping () -> Void
    ) {
        self.recipients = recipients
        self.onCopyInviteCode = onCopyInviteCode
        self.onSelectionChanged = onSelectionChanged
        self.onStopSharing = onStopSharing
        _selectedParticipantIDs = State(initialValue: Set(
            recipients
                .filter(\.isSelected)
                .map(\.participantID)
        ))
    }

    var body: some View {
        let model = CollaborationTerminalRecipientPopoverModel(recipientCount: recipients.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("AppIconLight", bundle: .main)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                Text(CollaborationStrings.terminalRecipientsShareTitle)
                    .cmuxFont(size: 12, weight: .semibold)
            }

            if model.showsInviteAction {
                Text(CollaborationStrings.terminalRecipientsEmpty)
                    .cmuxFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if model.showsStopSharingAction {
                        TrackedButton("terminal_share_stop", CollaborationStrings.stopSharingTerminal) {
                            onStopSharing()
                        }
                        .fixedSize()
                    }
                    Spacer()
                    TrackedButton("invite_code_copy", CollaborationStrings.copyInviteCode) {
                        onCopyInviteCode()
                    }
                    .buttonStyle(.mosaicAccent)
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
                }
            } else if model.showsRecipientSelection {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipients) { recipient in
                        Toggle(isOn: binding(for: recipient.participantID)) {
                            Text(recipient.displayName)
                                .cmuxFont(size: 11)
                                .lineLimit(1)
                        }
                        .toggleStyle(.mosaicAccentCheckbox)
                    }
                }

                if model.showsStopSharingAction {
                    HStack {
                        TrackedButton("terminal_share_stop", CollaborationStrings.stopSharingTerminal) {
                            onStopSharing()
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func binding(for participantID: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedParticipantIDs.contains(participantID)
            },
            set: { isSelected in
                if isSelected {
                    selectedParticipantIDs.insert(participantID)
                } else {
                    selectedParticipantIDs.remove(participantID)
                }
                // Checking/unchecking applies immediately: share with the person
                // on check, stop sharing with them on uncheck. There is no
                // separate confirm button.
                onSelectionChanged(selectedParticipantIDs)
            }
        )
    }
}

private struct AgentRoomWireDragPayload {
    static let contentType = UTType(exportedAs: CollaborationRuntime.agentRoomWirePasteboardTypeIdentifier)
}

private struct AgentRoomWireDragSourceRepresentable: NSViewRepresentable {
    let panel: TerminalPanel
    let onHoverChanged: (Bool) -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> AgentRoomWireDragSourceView {
        let view = AgentRoomWireDragSourceView(frame: .zero)
        view.panel = panel
        view.onHoverChanged = onHoverChanged
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: AgentRoomWireDragSourceView, context: Context) {
        nsView.panel = panel
        nsView.onHoverChanged = onHoverChanged
        nsView.onClick = onClick
    }
}

private final class AgentRoomWireDragSourceView: NSView, NSDraggingSource {
    weak var panel: TerminalPanel?
    var onHoverChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var mouseDownEvent: NSEvent?
    private var dragSessionActive = false
    private var dragSessionRanInCurrentPress = false
    private var closedHandCursorPushed = false
    /// Movement below this distance keeps a press behaving as a click; without
    /// it, 1pt of jitter silently turns the click into a wire drag that drops
    /// on its own surface and connects nothing.
    private static let dragStartThreshold: CGFloat = 4

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
        activeCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseMoved(with event: NSEvent) {
        activeCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        activeCursor.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragSessionActive = false
        dragSessionRanInCurrentPress = false
        pushClosedHandCursorIfNeeded()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragSessionActive,
              !dragSessionRanInCurrentPress,
              let panel,
              let mouseDownEvent else {
            return
        }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) >= Self.dragStartThreshold else {
            return
        }
        dragSessionActive = true
        dragSessionRanInCurrentPress = true
        // Compute the wire's start point fresh from this view (it exactly overlays
        // the link button) instead of trusting the layout-time anchor cache, which
        // can hold a stale screen point after the window moves.
        let buttonCenterInWindow = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let buttonCenterOnScreen = window.map {
            $0.convertToScreen(NSRect(origin: buttonCenterInWindow, size: .zero)).origin
        }
        CollaborationRuntime.shared.beginAgentRoomWireDrag(
            sourcePanel: panel,
            sourceScreenPoint: buttonCenterOnScreen,
            sourceWindow: window
        )
        pushClosedHandCursorIfNeeded()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            panel.id.uuidString,
            forType: NSPasteboard.PasteboardType(AgentRoomWireDragPayload.contentType.identifier)
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            if !dragSessionActive {
                popClosedHandCursorIfNeeded()
            }
        }
        // A mouseUp delivered around the end of a drag session must not count
        // as a click: the click toggles the room connection, so it would
        // disconnect the surface the wire drop just connected.
        guard !dragSessionActive, !dragSessionRanInCurrentPress else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let sourcePanel = panel
        endDragSession()
        // Portal layering can keep the SwiftUI header (and its link button)
        // from ever receiving the drop, so a button-to-button wire drag ends
        // with no operation and silently connects nothing. Recover by
        // connecting to the link button under the release point.
        if operation.isEmpty, let sourcePanel {
            CollaborationRuntime.shared.connectAgentRoomWireToLinkButton(
                near: screenPoint,
                sourceSurfaceID: sourcePanel.id
            )
        }
    }

    private func dragImage() -> NSImage {
        let imageSize = bounds.size.width > 0 && bounds.size.height > 0
            ? bounds.size
            : NSSize(width: 20, height: 20)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        return image
    }

    private func pushClosedHandCursorIfNeeded() {
        guard !closedHandCursorPushed else { return }
        NSCursor.closedHand.push()
        closedHandCursorPushed = true
    }

    private var activeCursor: NSCursor {
        closedHandCursorPushed ? .closedHand : .openHand
    }

    private func popClosedHandCursorIfNeeded() {
        guard closedHandCursorPushed else { return }
        NSCursor.pop()
        closedHandCursorPushed = false
    }

    private func endDragSession() {
        mouseDownEvent = nil
        dragSessionActive = false
        CollaborationRuntime.shared.endAgentRoomWireDrag()
        popClosedHandCursorIfNeeded()
    }

    private func setHovering(_ nextValue: Bool) {
        guard isHovering != nextValue else { return }
        isHovering = nextValue
        onHoverChanged?(nextValue)
    }

    deinit {
        onHoverChanged?(false)
        if dragSessionActive {
            Task { @MainActor in
                CollaborationRuntime.shared.endAgentRoomWireDrag()
            }
        }
        if closedHandCursorPushed {
            NSCursor.pop()
        }
    }
}

private struct AgentRoomWireAnchorRepresentable: NSViewRepresentable {
    let surfaceID: UUID

    func makeNSView(context: Context) -> AgentRoomWireAnchorView {
        let view = AgentRoomWireAnchorView(frame: .zero)
        view.surfaceID = surfaceID
        return view
    }

    func updateNSView(_ nsView: AgentRoomWireAnchorView, context: Context) {
        nsView.surfaceID = surfaceID
        nsView.noteAnchorChanged()
    }
}

private final class AgentRoomWireAnchorView: NSView {
    var surfaceID: UUID?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        noteAnchorChanged()
    }

    override func layout() {
        super.layout()
        noteAnchorChanged()
    }

    func noteAnchorChanged() {
        guard let surfaceID else { return }
        guard let window else {
            CollaborationRuntime.shared.removeAgentRoomWireAnchor(surfaceID: surfaceID, ownerID: ObjectIdentifier(self))
            return
        }
        let centerInView = NSPoint(x: bounds.midX, y: bounds.midY)
        let centerInWindow = convert(centerInView, to: nil)
        let centerScreenRect = window.convertToScreen(NSRect(origin: centerInWindow, size: .zero))
        CollaborationRuntime.shared.updateAgentRoomWireAnchor(
            surfaceID: surfaceID,
            screenPoint: centerScreenRect.origin,
            window: window,
            ownerID: ObjectIdentifier(self)
        )
    }

    deinit {
        guard let surfaceID else { return }
        let ownerID = ObjectIdentifier(self)
        Task { @MainActor in
            CollaborationRuntime.shared.removeAgentRoomWireAnchor(surfaceID: surfaceID, ownerID: ownerID)
        }
    }
}

private struct AgentHibernationPlaceholderView: View {
    let state: AgentHibernationPanelState
    let appearance: PanelAppearance
    let onResume: () -> Void

    private var lastActivityText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.lastActivityAt, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 14) {
            CmuxSystemSymbolImage(magnified: "pause.circle", pointSize: 34, weight: .regular)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(String(localized: "terminal.agentHibernation.title", defaultValue: "Agent hibernated"))
                    .cmuxFont(.headline)
                Text(state.agentDisplayName)
                    .cmuxFont(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "terminal.agentHibernation.lastActivity", defaultValue: "Last activity %@"),
                        lastActivityText
                    )
                )
                .cmuxFont(.caption)
                .foregroundStyle(.tertiary)
            }
            TrackedButton("terminalpanelview_button_859", String(localized: "terminal.agentHibernation.resume", defaultValue: "Resume")) {
                onResume()
            }
            .buttonStyle(.mosaicAccent)
            .accessibilityIdentifier("AgentHibernationResumeButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.contentBackgroundColor))
    }
}

#if DEBUG
private extension View {
    func reportTerminalViewportGeometryForUITest(panel: TerminalPanel) -> some View {
        modifier(TerminalViewportGeometryReporter(panel: panel))
    }
}

private struct TerminalViewportGeometryReporter: ViewModifier {
    @ObservedObject var panel: TerminalPanel

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        recordTerminalViewportGeometryForUITest(proxy: proxy, panel: panel)
                    }
                    .onChange(of: proxy.size) {
                        recordTerminalViewportGeometryForUITest(proxy: proxy, panel: panel)
                    }
            }
        }
    }
}

@MainActor
private func recordTerminalViewportGeometryForUITest(proxy: GeometryProxy, panel: TerminalPanel) {
    let env = ProcessInfo.processInfo.environment
    guard env["CMUX_UI_TEST_TERMINAL_VIEWPORT_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return
    }

    let hostedView = panel.hostedView
    let hostedFrame = hostedView.frame
    let hostedBounds = hostedView.bounds
    let hostedSuperviewBounds = hostedView.superview?.bounds ?? .zero
    let windowContentBounds = hostedView.window?.contentView?.bounds ?? .zero
    let hostedFrameInContent: NSRect
    if let contentView = hostedView.window?.contentView {
        hostedFrameInContent = contentView.convert(hostedView.convert(hostedView.bounds, to: nil), from: nil)
    } else {
        hostedFrameInContent = .zero
    }

    _ = UITestCaptureSink().mutateJSONObjectIfConfigured(envKey: "CMUX_UI_TEST_TERMINAL_VIEWPORT_PATH") { payload in
        payload["terminalViewportPanelId"] = panel.id.uuidString
        payload["terminalViewportPanelWidth"] = terminalViewportFormat(proxy.size.width)
        payload["terminalViewportPanelHeight"] = terminalViewportFormat(proxy.size.height)
        payload["terminalViewportHostedFrameMinX"] = terminalViewportFormat(hostedFrame.minX)
        payload["terminalViewportHostedFrameMinY"] = terminalViewportFormat(hostedFrame.minY)
        payload["terminalViewportHostedFrameMaxX"] = terminalViewportFormat(hostedFrame.maxX)
        payload["terminalViewportHostedFrameMaxY"] = terminalViewportFormat(hostedFrame.maxY)
        payload["terminalViewportHostedFrameWidth"] = terminalViewportFormat(hostedFrame.width)
        payload["terminalViewportHostedFrameHeight"] = terminalViewportFormat(hostedFrame.height)
        payload["terminalViewportHostedBoundsWidth"] = terminalViewportFormat(hostedBounds.width)
        payload["terminalViewportHostedBoundsHeight"] = terminalViewportFormat(hostedBounds.height)
        payload["terminalViewportHostedSuperviewWidth"] = terminalViewportFormat(hostedSuperviewBounds.width)
        payload["terminalViewportHostedSuperviewHeight"] = terminalViewportFormat(hostedSuperviewBounds.height)
        payload["terminalViewportWindowContentWidth"] = terminalViewportFormat(windowContentBounds.width)
        payload["terminalViewportWindowContentHeight"] = terminalViewportFormat(windowContentBounds.height)
        payload["terminalViewportHostedContentMinX"] = terminalViewportFormat(hostedFrameInContent.minX)
        payload["terminalViewportHostedContentMinY"] = terminalViewportFormat(hostedFrameInContent.minY)
        payload["terminalViewportHostedContentMaxX"] = terminalViewportFormat(hostedFrameInContent.maxX)
        payload["terminalViewportHostedContentMaxY"] = terminalViewportFormat(hostedFrameInContent.maxY)
    }
}

private func terminalViewportFormat(_ value: CGFloat) -> String {
    String(format: "%.3f", Double(value))
}
#endif

/// Shared appearance settings for panels
struct PanelAppearance {
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let dividerColor: Color
    let unfocusedOverlayNSColor: NSColor
    let unfocusedOverlayOpacity: Double
    let usesClearContentBackground: Bool

    var contentBackgroundColor: NSColor {
        usesClearContentBackground ? .clear : backgroundColor
    }

    var drawsContentBackground: Bool {
        !usesClearContentBackground
    }

    static func fromConfig(_ config: GhosttyConfig) -> PanelAppearance {
        fromConfig(
            config,
            usesTransparentWindow: WindowBackgroundComposition.policy
                .shouldUseTransparentBackgroundWindow(glassEffectAvailable: false)
        )
    }

    static func fromConfig(_ config: GhosttyConfig, usesTransparentWindow: Bool) -> PanelAppearance {
        let backgroundColor = MosaicChromePalette.workspaceBackgroundColor
        return PanelAppearance(
            backgroundColor: backgroundColor,
            foregroundColor: cmuxReadableForegroundNSColor(
                preferred: config.foregroundColor,
                on: backgroundColor
            ),
            dividerColor: Color(nsColor: config.resolvedSplitDividerColor),
            unfocusedOverlayNSColor: config.unfocusedSplitOverlayFill,
            unfocusedOverlayOpacity: config.unfocusedSplitOverlayOpacity,
            usesClearContentBackground: shouldUseClearContentBackground(
                opacity: config.backgroundOpacity,
                usesGhosttyGlassStyle: config.backgroundBlur.isMacOSGlassStyle,
                usesTransparentWindow: usesTransparentWindow
            )
        )
    }

    static func shouldUseClearContentBackground(
        opacity: Double,
        usesGhosttyGlassStyle: Bool,
        usesTransparentWindow: Bool
    ) -> Bool {
        usesTransparentWindow || usesGhosttyGlassStyle || opacity < 0.999
    }
}
