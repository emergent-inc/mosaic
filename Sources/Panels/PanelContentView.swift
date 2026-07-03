import CmuxFoundation
import SwiftUI
import Foundation
import Bonsplit
import AppKit
import CmuxAppKitSupportUI

/// View that renders the appropriate panel view based on panel type
struct PanelContentView: View {
    let panel: any Panel
    let workspaceId: UUID
    let paneId: PaneID
    let isFocused: Bool
    let isSelectedInPane: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let windowAppearance: WindowAppearanceSnapshot
    let customSidebarTabManager: TabManager?
    let customSidebarUnread: SidebarUnreadModel = TerminalNotificationStore.shared.sidebarUnread
    let hasUnreadNotification: Bool
    let terminalAgentContext: String
    /// Explicit browser pane-ownership signal for hosts whose panels live outside
    /// the main `Workspace` tree (the Dock). `nil` keeps the main-area behavior.
    var paneOwnershipOverride: Bool? = nil
    let onFocus: () -> Void
    let onRequestPanelFocus: () -> Void
    let onResumeAgentHibernation: () -> Void
    let onAutoResumeAgentHibernation: () -> Void
    let onTriggerFlash: () -> Void

    var body: some View {
        renderedPanel
            .overlay {
                paneDropTargetOverlay
            }
    }

    @ViewBuilder
    private var renderedPanel: some View {
        switch panel.panelType {
        case .terminal:
            if let terminalPanel = panel as? TerminalPanel {
                TerminalPanelView(
                    panel: terminalPanel,
                    paneId: paneId,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    isSplit: isSplit,
                    appearance: appearance,
                    hasUnreadNotification: hasUnreadNotification,
                    terminalAgentContext: terminalAgentContext,
                    onFocus: onFocus,
                    onResumeAgentHibernation: onResumeAgentHibernation,
                    onAutoResumeAgentHibernation: onAutoResumeAgentHibernation,
                    onTriggerFlash: onTriggerFlash
                )
            }
        case .browser:
            if let browserPanel = panel as? BrowserPanel {
                BrowserPanelView(
                    panel: browserPanel,
                    paneId: paneId,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    paneOwnershipOverride: paneOwnershipOverride,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .markdown:
            if let markdownPanel = panel as? MarkdownPanel {
                MarkdownPanelView(
                    panel: markdownPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .filePreview:
            if let filePreviewPanel = panel as? FilePreviewPanel {
                FilePreviewPanelView(
                    panel: filePreviewPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .rightSidebarTool:
            if let rightSidebarToolPanel = panel as? RightSidebarToolPanel {
                RightSidebarToolPanelView(
                    panel: rightSidebarToolPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .customSidebar:
            if let customSidebarPanel = panel as? CustomSidebarPanel {
                if let customSidebarTabManager {
                    CustomSidebarPanelView(
                        panel: customSidebarPanel,
                        tabManager: customSidebarTabManager,
                        sidebarUnread: customSidebarUnread,
                        isFocused: isFocused,
                        isVisibleInUI: isVisibleInUI,
                        appearance: appearance,
                        windowAppearance: windowAppearance,
                        onRequestPanelFocus: onRequestPanelFocus
                    )
                }
            }
        case .agentSession:
            if let agentSessionPanel = panel as? AgentSessionPanel {
                AgentSessionPanelView(
                    panel: agentSessionPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .project:
            if let projectPanel = panel as? ProjectPanel {
                ProjectPanelView(
                    panel: projectPanel,
                    isFocused: isFocused,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .extensionBrowser:
            if let extensionBrowserPanel = panel as? CMUXSidebarExtensionBrowserPanel {
                CMUXSidebarExtensionBrowserPanelView(
                    panel: extensionBrowserPanel,
                    onRequestPanelFocus: onRequestPanelFocus
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var paneDropTargetOverlay: some View {
        if shouldInstallPaneDropTarget {
            PaneDropTargetRepresentable(dropContext: PaneDropContext(
                workspaceId: workspaceId,
                panelId: panel.id,
                paneId: paneId
            ))
        }
    }

    private var shouldInstallPaneDropTarget: Bool {
        guard isVisibleInUI else { return false }
        switch panel.panelType {
        case .markdown, .filePreview, .rightSidebarTool, .customSidebar, .agentSession, .project, .extensionBrowser:
            return true
        case .terminal, .browser:
            return false
        }
    }
}

struct PanelFilePathHeader<TrailingContent: View>: View {
    let iconSystemName: String
    let filePath: String
    let foregroundColor: NSColor
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: 8) {
            CmuxSystemSymbolImage(systemName: iconSystemName, pointSize: 16)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(filePath)
                .cmuxFont(size: 11, design: .monospaced)
                .foregroundStyle(Color(nsColor: foregroundColor).opacity(0.68))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            trailingContent()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.clear)
    }
}

struct PanelHeaderIconButton: View {
    let systemName: String
    let label: String
    var isDisabled: Bool = false
    var hoverCursor: NSCursor = .pointingHand
    var hoverBackgroundColor: Color = .primary
    var hoverForegroundColor: Color? = nil
    var isHoverForced: Bool = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        TrackedButton("panelcontentview_button_211", action: action) {
            PanelHeaderIconGlyph(systemName: systemName)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(backgroundColor)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .foregroundColor(foregroundColor)
        .disabled(isDisabled)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            isHovering = hovering
        }
        .cmuxCursorOnHover(hoverCursor, enabled: !isDisabled && isEnabled)
    }

    private var effectiveIsHovering: Bool {
        (isHovering || isHoverForced) && isEnabled && !isDisabled
    }

    private var backgroundColor: Color {
        if effectiveIsHovering {
            return hoverBackgroundColor.opacity(0.14)
        }
        return Color.primary.opacity(isEnabled ? 0.08 : 0.04)
    }

    private var borderColor: Color {
        if effectiveIsHovering {
            return hoverBackgroundColor.opacity(0.24)
        }
        return Color.primary.opacity(isEnabled ? 0.14 : 0.06)
    }

    private var foregroundColor: Color {
        if effectiveIsHovering, let hoverForegroundColor {
            return hoverForegroundColor
        }
        return .secondary
    }
}

struct PanelHeaderIconGlyph: View {
    let systemName: String

    var body: some View {
        CmuxSystemSymbolImage(systemName: systemName, pointSize: 13)
            .frame(width: 20, height: 20, alignment: .center)
            .contentShape(Rectangle())
    }
}

struct CmuxHoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    let enabled: Bool
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, enabled {
                    pushIfNeeded()
                } else {
                    popIfNeeded()
                }
            }
            .onChange(of: enabled) { _, nextEnabled in
                if !nextEnabled {
                    popIfNeeded()
                }
            }
            .onDisappear {
                popIfNeeded()
            }
    }

    private func pushIfNeeded() {
        guard !cursorPushed else { return }
        cursor.push()
        cursorPushed = true
    }

    private func popIfNeeded() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }
}

extension View {
    func cmuxCursorOnHover(_ cursor: NSCursor, enabled: Bool = true) -> some View {
        modifier(CmuxHoverCursorModifier(cursor: cursor, enabled: enabled))
    }
}
