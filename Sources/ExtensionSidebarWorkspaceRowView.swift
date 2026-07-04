import MosaicFoundation
import AppKit
import MosaicSidebarProviderKit
import SwiftUI
import WebKit

struct MosaicExtensionSidebarWorkspaceRowView: View, Equatable {
    let row: MosaicSidebarProviderRow
    let workspace: MosaicSidebarProviderWorkspace?
    let providerId: String
    let relativeNow: Date
    let isSelected: Bool
    let onSelect: (UUID) -> Void
    let onOpenWindow: (MosaicSidebarProviderWorkspace) -> Void
    @State private var showsInspector = false
    @State private var inspectorDraft: MosaicExtensionWorkspaceInspectorDraft?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row &&
            lhs.workspace == rhs.workspace &&
            lhs.providerId == rhs.providerId &&
            lhs.relativeNow == rhs.relativeNow &&
            lhs.isSelected == rhs.isSelected
    }

    private var isSuperCompact: Bool {
        false
    }

    private var isThin: Bool {
        false
    }

    var body: some View {
        let primarySize: CGFloat = isSuperCompact ? 10.5 : 12.5
        let secondarySize: CGFloat = isSuperCompact ? 9 : 10
        HStack(spacing: isSuperCompact ? 5 : 7) {
            VStack(alignment: .leading, spacing: isSuperCompact ? 0 : 2) {
                Text(row.title)
                    .mosaicFont(size: primarySize, weight: .regular)
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !isSuperCompact, let subtitle = rendered(row.subtitle) {
                    Text(subtitle)
                        .mosaicFont(size: secondarySize, weight: .regular)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isSuperCompact, let trailing = rendered(row.trailingText) {
                Text(trailing)
                    .mosaicFont(size: 10.5, weight: .regular)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let accessory = row.accessory, let workspace {
                TrackedButton("extensionsidebarworkspacerowview_button_63", action: {
                    if inspectorDraft == nil {
                        inspectorDraft = MosaicExtensionWorkspaceInspectorDraft.initial(
                            workspace: workspace,
                            selectedTab: accessory.defaultTab
                        )
                    }
                    showsInspector = true
                }) {
                    Image(systemName: accessory.systemImageName)
                        .mosaicFont(size: isSuperCompact ? 10 : 12, weight: .regular)
                        .frame(width: isSuperCompact ? 14 : 18, height: isSuperCompact ? 14 : 18)
                }
                .buttonStyle(.plain)
                .safeHelp(String(localized: "sidebar.extension.inspectWorkspace", defaultValue: "Workspace tools"))
                .popover(isPresented: $showsInspector, arrowEdge: .trailing) {
                    MosaicExtensionWorkspaceInspectorView(
                        workspace: workspace,
                        draft: Binding(
                            get: {
                                inspectorDraft ?? MosaicExtensionWorkspaceInspectorDraft.initial(
                                    workspace: workspace,
                                    selectedTab: accessory.defaultTab
                                )
                            },
                            set: { inspectorDraft = $0 }
                        ),
                        onOpenWindow: { onOpenWindow(workspace) }
                    )
                    .frame(width: 460, height: 340)
                }
            }
        }
        .padding(.leading, isSuperCompact ? 14 : 28)
        .padding(.trailing, 8)
        .padding(.vertical, isSuperCompact ? 2 : (isThin ? 5 : 7))
        .frame(minHeight: isSuperCompact ? 22 : 32)
        .background {
            if isSelected {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(row.workspaceId)
        }
    }

    private func rendered(_ text: MosaicSidebarProviderText?) -> String? {
        guard let text else { return nil }
        switch text {
        case .plain(let value):
            return value
        case .localized(let localized):
            return MosaicExtensionSidebarSelection.localizedText(localized)
        case .relativeDate(let date, _):
            return MosaicExtensionRelativeTimeFormatter.string(from: date, to: relativeNow)
        }
    }
}

struct MosaicExtensionWorkspaceInspectorDraft: Equatable {
    var selectedTab: MosaicSidebarProviderWorkspacePopoverTab
    var notes: String
    var address: String
    var committedAddress: String

    static func initial(
        workspace: MosaicSidebarProviderWorkspace,
        selectedTab: MosaicSidebarProviderWorkspacePopoverTab = .notes
    ) -> MosaicExtensionWorkspaceInspectorDraft {
        let initialAddress = workspace.pullRequestURLs.first ?? "https://github.com/"
        return MosaicExtensionWorkspaceInspectorDraft(
            selectedTab: selectedTab,
            notes: "",
            address: initialAddress,
            committedAddress: initialAddress
        )
    }
}

enum MosaicExtensionRelativeTimeFormatter {
    static func string(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return String(localized: "relativeTime.now", defaultValue: "now") }
        let minutes = seconds / 60
        if minutes < 60 { return localizedCount("relativeTime.minutes", defaultValue: "%lldm", count: minutes) }
        let hours = minutes / 60
        if hours < 24 { return localizedCount("relativeTime.hours", defaultValue: "%lldh", count: hours) }
        let days = hours / 24
        if days < 7 { return localizedCount("relativeTime.days", defaultValue: "%lldd", count: days) }
        let weeks = days / 7
        return localizedCount("relativeTime.weeks", defaultValue: "%lldw", count: weeks)
    }

    private static func localizedCount(_ key: String, defaultValue: String, count: Int) -> String {
        let format = NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .main,
            value: defaultValue,
            comment: ""
        )
        return String.localizedStringWithFormat(format, Int64(count))
    }
}

struct MosaicExtensionWorkspaceInspectorView: View {
    let workspace: MosaicSidebarProviderWorkspace
    let onOpenWindow: () -> Void
    @Binding private var draft: MosaicExtensionWorkspaceInspectorDraft

    init(
        workspace: MosaicSidebarProviderWorkspace,
        draft: Binding<MosaicExtensionWorkspaceInspectorDraft>,
        onOpenWindow: @escaping () -> Void
    ) {
        self.workspace = workspace
        self._draft = draft
        self.onOpenWindow = onOpenWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $draft.selectedTab) {
                    Text(String(localized: "sidebar.extension.notesTab", defaultValue: "Notes")).tag(MosaicSidebarProviderWorkspacePopoverTab.notes)
                    Text(String(localized: "sidebar.extension.browserTab", defaultValue: "Browser")).tag(MosaicSidebarProviderWorkspacePopoverTab.browser)
                }
                .pickerStyle(.segmented)

                TrackedButton("extensionsidebarworkspacerowview_button_195", action: onOpenWindow) {
                    Image(systemName: "macwindow")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .safeHelp(String(localized: "sidebar.extension.openWindow", defaultValue: "Open window"))
            }
            .padding(10)

            Divider()

            switch draft.selectedTab {
            case .notes:
                TextEditor(text: $draft.notes)
                    .mosaicFont(size: 13)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .accessibilityIdentifier("ExtensionSidebarNotesEditor")
            case .browser, .pullRequest:
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(
                            String(localized: "sidebar.extension.browserAddress", defaultValue: "Search or enter URL"),
                            text: $draft.address
                        )
                        .textFieldStyle(.plain)
                        .onSubmit {
                            let normalized = MosaicExtensionWorkspaceInspectorBrowserView.normalizedAddress(draft.address)
                            draft.address = normalized
                            draft.committedAddress = normalized
                        }
                    }
                    .mosaicFont(size: 12)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor))

                    MosaicExtensionWorkspaceInspectorBrowserView(address: draft.committedAddress)
                }
            }
        }
    }
}

struct MosaicExtensionWorkspaceInspectorWindowContentView: View {
    let workspace: MosaicSidebarProviderWorkspace
    let onOpenWindow: () -> Void
    @State private var draft: MosaicExtensionWorkspaceInspectorDraft

    init(
        workspace: MosaicSidebarProviderWorkspace,
        onOpenWindow: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onOpenWindow = onOpenWindow
        _draft = State(initialValue: MosaicExtensionWorkspaceInspectorDraft.initial(workspace: workspace))
    }

    var body: some View {
        MosaicExtensionWorkspaceInspectorView(
            workspace: workspace,
            draft: $draft,
            onOpenWindow: onOpenWindow
        )
    }
}

struct MosaicExtensionWorkspaceInspectorBrowserView: NSViewRepresentable {
    let address: String

    final class Coordinator {
        var loadedAddress: String?
    }

    static func normalizedAddress(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "https://github.com/" }
        if trimmed.contains("://") { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://\(trimmed)" }
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://www.google.com/search?q=\(query)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let normalized = Self.normalizedAddress(address)
        guard context.coordinator.loadedAddress != normalized,
              let url = URL(string: normalized) else {
            return
        }
        context.coordinator.loadedAddress = normalized
        webView.load(URLRequest(url: url))
    }
}

@MainActor
final class MosaicExtensionSidebarInspectorWindowController {
    private static var controllers: [UUID: NSWindowController] = [:]
    private static var closeObservers: [UUID: NSObjectProtocol] = [:]

    static func show(workspace: MosaicSidebarProviderWorkspace) {
        if let controller = controllers[workspace.id] {
            controller.window?.title = workspace.title
            controller.window?.setContentSize(NSSize(width: 620, height: 440))
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = MosaicExtensionWorkspaceInspectorWindowContentView(workspace: workspace) {
            show(workspace: workspace)
        }
        let hostingController = NSHostingController(rootView: view.frame(width: 620, height: 440))
        let window = NSWindow(contentViewController: hostingController)
        window.title = workspace.title
        window.identifier = NSUserInterfaceItemIdentifier("mosaic.extensionSidebarInspector")
        window.setContentSize(NSSize(width: 620, height: 440))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let controller = NSWindowController(window: window)
        controllers[workspace.id] = controller
        closeObservers[workspace.id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                controllers.removeValue(forKey: workspace.id)
                if let observer = closeObservers.removeValue(forKey: workspace.id) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
