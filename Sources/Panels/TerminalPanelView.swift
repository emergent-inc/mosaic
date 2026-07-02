import SwiftUI
import Foundation
import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxTestSupport
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
    @State private var isTerminalRecipientPopoverPresented = false
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
        .onDrop(of: [AgentRoomWireDragPayload.contentType], isTargeted: nil) { providers in
            handleAgentRoomWireDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyConfigDidReload)) { _ in
            terminalFontSize = GhosttyConfig.load(globalFontMagnificationPercent: GlobalFontMagnification.storedPercent).fontSize
        }
    }

    private var terminalHeader: some View {
        let state = CollaborationRuntime.shared.state(for: panel)
        let agentRoomState = CollaborationRuntime.shared.agentRoomState(for: panel)
        return HStack(spacing: 8) {
            CmuxSystemSymbolImage(systemName: panel.displayIcon ?? "terminal.fill", pointSize: 16)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(panel.displayTitle)
                .cmuxFont(size: 11, design: .monospaced)
                .foregroundStyle(Color(nsColor: appearance.foregroundColor).opacity(0.68))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if state.isShared {
                Text(state.peerSummary)
                    .cmuxFont(size: 10)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            agentRoomStatusView(state: agentRoomState)
            terminalAgentRoomButton
            terminalCollaborationButton
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.clear)
    }

    @ViewBuilder
    private func agentRoomStatusView(state: AgentRoomHeaderState) -> some View {
        if state.isConnected {
            HStack(spacing: 4) {
                CmuxSystemSymbolImage(systemName: "link", pointSize: 9, weight: .semibold)
                Text(state.label)
                    .cmuxFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor))
            .accessibilityIdentifier("TerminalAgentRoomConnectedPill")
        }
    }

    private var terminalCollaborationButton: some View {
        let state = CollaborationRuntime.shared.state(for: panel)
        let canManageRecipients = CollaborationRuntime.shared.canManageRecipients(for: panel)
        let label = if state.isShared && canManageRecipients {
            CollaborationStrings.manageTerminalSharing
        } else if state.isShared {
            CollaborationStrings.stopSharingTerminal
        } else {
            CollaborationStrings.shareTerminal
        }
        return PanelHeaderIconButton(
            systemName: state.isShared ? "person.2.fill" : "person.2",
            label: label,
            isDisabled: false,
            action: {
                if state.isShared && canManageRecipients {
                    isTerminalRecipientPopoverPresented = true
                } else {
                    CollaborationRuntime.shared.configureOrShare(terminal: panel)
                }
            }
        )
        .foregroundColor(state.isShared ? .accentColor : .secondary)
        .accessibilityIdentifier("TerminalCollaborationButton")
        .popover(isPresented: $isTerminalRecipientPopoverPresented, arrowEdge: .bottom) {
            TerminalCollaborationRecipientPopoverContent(
                recipients: CollaborationRuntime.shared.recipientSnapshots(for: panel),
                onShare: { selectedIDs in
                    CollaborationRuntime.shared.applyRecipientSelection(selectedIDs, for: panel)
                    isTerminalRecipientPopoverPresented = false
                }
            )
        }
    }

    private var terminalAgentRoomButton: some View {
        let state = CollaborationRuntime.shared.agentRoomState(for: panel)
        return PanelHeaderIconButton(
            systemName: state.isConnected ? "link.circle.fill" : "link.circle",
            label: state.label,
            isDisabled: false,
            action: {
                CollaborationRuntime.shared.connectAgentRoomFromHeader(panel: panel)
            }
        )
        .foregroundColor(state.isConnected ? .accentColor : .secondary)
        .accessibilityIdentifier("TerminalAgentRoomButton")
        .background(AgentRoomWireAnchorRepresentable(surfaceID: panel.id))
        .onDrag {
            CollaborationRuntime.shared.beginAgentRoomWireDrag(sourcePanel: panel)
            return AgentRoomWireDragPayload.provider(for: panel.id)
        }
    }

    private func handleAgentRoomWireDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(AgentRoomWireDragPayload.contentType.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: AgentRoomWireDragPayload.contentType.identifier) { data, _ in
            guard let sourceSurfaceID = AgentRoomWireDragPayload.surfaceID(from: data) else { return }
            Task { @MainActor in
                CollaborationRuntime.shared.connectAgentRoomWire(
                    sourceSurfaceID: sourceSurfaceID,
                    targetPanel: panel
                )
            }
        }
        return true
    }
}

private struct TerminalCollaborationRecipientPopoverContent: View {
    let recipients: [CollaborationTerminalRecipientSnapshot]
    let onShare: (Set<String>) -> Void
    @State private var selectedParticipantIDs: Set<String>

    init(
        recipients: [CollaborationTerminalRecipientSnapshot],
        onShare: @escaping (Set<String>) -> Void
    ) {
        self.recipients = recipients
        self.onShare = onShare
        _selectedParticipantIDs = State(initialValue: Set(
            recipients
                .filter(\.isSelected)
                .map(\.participantID)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CollaborationStrings.terminalRecipientsTitle)
                .cmuxFont(size: 12, weight: .semibold)

            if recipients.isEmpty {
                Text(CollaborationStrings.terminalRecipientsEmpty)
                    .cmuxFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipients) { recipient in
                        Toggle(isOn: binding(for: recipient.participantID)) {
                            Text(recipient.displayName)
                                .cmuxFont(size: 11)
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack {
                Spacer()
                Button(CollaborationStrings.share) {
                    onShare(selectedParticipantIDs)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 240)
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
            }
        )
    }
}

private struct AgentRoomWireDragPayload {
    static let contentType = UTType(exportedAs: CollaborationRuntime.agentRoomWirePasteboardTypeIdentifier)

    static func provider(for surfaceID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(surfaceID.uuidString.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func surfaceID(from data: Data?) -> String? {
        guard let data,
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: trimmed).map { $0.uuidString }
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
            CollaborationRuntime.shared.removeAgentRoomWireAnchor(surfaceID: surfaceID)
            return
        }
        let centerInView = NSPoint(x: bounds.midX, y: bounds.midY)
        let centerInWindow = convert(centerInView, to: nil)
        let centerScreenRect = window.convertToScreen(NSRect(origin: centerInWindow, size: .zero))
        CollaborationRuntime.shared.updateAgentRoomWireAnchor(
            surfaceID: surfaceID,
            screenPoint: centerScreenRect.origin,
            window: window
        )
    }

    deinit {
        guard let surfaceID else { return }
        Task { @MainActor in
            CollaborationRuntime.shared.removeAgentRoomWireAnchor(surfaceID: surfaceID)
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
            Button(String(localized: "terminal.agentHibernation.resume", defaultValue: "Resume")) {
                onResume()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
        let backgroundColor = GhosttyBackgroundTheme.color(
            backgroundColor: config.backgroundColor,
            opacity: config.backgroundOpacity
        )
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
