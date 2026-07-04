import MosaicFoundation
@_spi(MosaicHostTransport) import MosaicSidebar
@_spi(MosaicHostTransport) import MosaicExtensionKit
import AppKit
import ExtensionFoundation
import SwiftUI

private struct MosaicSidebarExtensionGrant: Codable, Equatable {
    var manifestID: String
    var manifestDisplayName: String
    var apiVersion: MosaicExtensionAPIVersion
    var readScopes: Set<MosaicExtensionScope>
    var actionScopes: Set<MosaicExtensionActionScope>
}

private struct MosaicSidebarExtensionEffectiveGrant: Equatable {
    var manifest: MosaicExtensionManifest
    var readScopes: Set<MosaicExtensionScope>
    var actionScopes: Set<MosaicExtensionActionScope>

    var needsAdditionalApproval: Bool {
        !readScopes.isSuperset(of: manifest.readScopes) ||
            !actionScopes.isSuperset(of: manifest.actionScopes)
    }

    var hasSensitiveAccess: Bool {
        readScopes.contains { !MosaicSidebarExtensionGrantStore.defaultReadScopes.contains($0) } ||
            actionScopes.contains { !MosaicSidebarExtensionGrantStore.defaultActionScopes.contains($0) }
    }
}

private struct MosaicSidebarExtensionGrantStore {
    static let defaultReadScopes: Set<MosaicExtensionScope> = []
    static let defaultActionScopes: Set<MosaicExtensionActionScope> = []

    private static let defaultsKey = "mosaicExtensionSidebar.grants.v1"

    var defaults: UserDefaults = .standard

    func effectiveGrant(
        bundleIdentifier: String,
        manifest: MosaicExtensionManifest
    ) -> MosaicSidebarExtensionEffectiveGrant {
        let requestedReadScopes = Set(manifest.readScopes)
        let requestedActionScopes = Set(manifest.actionScopes)
        guard let grant = storedGrants()[bundleIdentifier],
              grant.manifestID == manifest.id,
              grant.apiVersion == manifest.minimumAPIVersion else {
            return MosaicSidebarExtensionEffectiveGrant(
                manifest: manifest,
                readScopes: requestedReadScopes.intersection(Self.defaultReadScopes),
                actionScopes: requestedActionScopes.intersection(Self.defaultActionScopes)
            )
        }
        return MosaicSidebarExtensionEffectiveGrant(
            manifest: manifest,
            readScopes: requestedReadScopes.intersection(grant.readScopes),
            actionScopes: requestedActionScopes.intersection(grant.actionScopes)
        )
    }

    func grantRequestedAccess(bundleIdentifier: String, manifest: MosaicExtensionManifest) {
        updateGrant(
            bundleIdentifier: bundleIdentifier,
            manifest: manifest,
            readScopes: Set(manifest.readScopes),
            actionScopes: Set(manifest.actionScopes)
        )
    }

    func revokeSensitiveAccess(bundleIdentifier: String, manifest: MosaicExtensionManifest) {
        updateGrant(
            bundleIdentifier: bundleIdentifier,
            manifest: manifest,
            readScopes: Set(manifest.readScopes).intersection(Self.defaultReadScopes),
            actionScopes: Set(manifest.actionScopes).intersection(Self.defaultActionScopes)
        )
    }

    private func updateGrant(
        bundleIdentifier: String,
        manifest: MosaicExtensionManifest,
        readScopes: Set<MosaicExtensionScope>,
        actionScopes: Set<MosaicExtensionActionScope>
    ) {
        var grants = storedGrants()
        grants[bundleIdentifier] = MosaicSidebarExtensionGrant(
            manifestID: manifest.id,
            manifestDisplayName: manifest.displayName,
            apiVersion: manifest.minimumAPIVersion,
            readScopes: readScopes,
            actionScopes: actionScopes
        )
        save(grants)
    }

    private func storedGrants() -> [String: MosaicSidebarExtensionGrant] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: MosaicSidebarExtensionGrant].self, from: data)) ?? [:]
    }

    private func save(_ grants: [String: MosaicSidebarExtensionGrant]) {
        if let data = try? JSONEncoder().encode(grants) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

private struct MosaicSidebarExtensionLimitedChoiceStore {
    private static let defaultsKey = "mosaicExtensionSidebar.limitedChoices.v1"

    var defaults: UserDefaults = .standard

    func choices() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func insert(_ key: String) {
        var choices = choices()
        choices.insert(key)
        save(choices)
    }

    func remove(_ key: String) {
        var choices = choices()
        choices.remove(key)
        save(choices)
    }

    private func save(_ choices: Set<String>) {
        defaults.set(choices.sorted(), forKey: Self.defaultsKey)
    }
}

struct MosaicInstalledExtensionSidebarHostView: View {
    private static let selectedExtensionBundleIDDefaultsKey = "mosaicExtensionSidebar.selectedExtensionBundleId"
    private static let selectedExtensionNameDefaultsKey = "mosaicExtensionSidebar.selectedExtensionName"

    var snapshotProvider: @MainActor () -> MosaicSidebarSnapshot
    var snapshotUpdateToken: UInt64 = 0
    var actionHandler: @MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult
    var onUseDefaultSidebar: @MainActor () -> Void = {}

    @State private var identity: AppExtensionIdentity?
    @State private var enabledIdentities: [AppExtensionIdentity] = []
    @State private var selectedExtensionBundleID = UserDefaults.standard.string(
        forKey: Self.selectedExtensionBundleIDDefaultsKey
    )
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var disabledExtensionCount = 0
    @State private var unapprovedExtensionCount = 0
    @State private var browserAnchorView: NSView?
    @State private var xpcHost = MosaicSidebarExtensionHostXPC()
    @State private var effectiveGrant: MosaicSidebarExtensionEffectiveGrant?
    @State private var blockedManifestReason: String?
    @State private var isShowingExtensionDetails = false
    @State private var isShowingAccessReview = false
    @State private var keptLimitedManifestKeys = MosaicSidebarExtensionLimitedChoiceStore().choices()
    @State private var hostReloadToken: UInt64 = 0

    var body: some View {
        Group {
            if let identity {
                VStack(alignment: .leading, spacing: 0) {
                    extensionControlStrip(activeIdentity: identity)
                    if let effectiveGrant, shouldShowAccessBanner(identity: identity, effectiveGrant: effectiveGrant) {
                        extensionAccessBanner(identity: identity, effectiveGrant: effectiveGrant)
                    }
                    MosaicSidebarExtensionHostView(
                        identity: identity,
                        onConnection: { connection in
                            xpcHost.attach(
                                connection: connection,
                                bundleIdentifier: identity.bundleIdentifier,
                                snapshotProvider: snapshotProvider,
                                actionHandler: actionHandler,
                                onGrantChanged: { grant in
                                    effectiveGrant = grant
                                },
                                onManifestBlocked: { reason in
                                    blockedManifestReason = reason
                                }
                            )
                        },
                        onDeactivation: { error in
                            xpcHost.invalidate()
                            effectiveGrant = nil
                            if self.identity?.bundleIdentifier == identity.bundleIdentifier {
                                blockedManifestReason = "connectionInterrupted"
                            }
                            errorText = error?.localizedDescription
                        },
                        onTeardown: {
                            xpcHost.invalidate()
                        }
                    )
                    .id("\(identity.bundleIdentifier)-\(hostReloadToken)")
                    .opacity(blockedManifestReason == nil ? 1 : 0)
                    .frame(height: blockedManifestReason == nil ? nil : 0)
                    .accessibilityIdentifier("MosaicExtensionSidebarHostView")
                    .padding(.top, effectiveGrant?.needsAdditionalApproval == true ? 8 : 0)
                    if let blockedManifestReason {
                        blockedExtensionView(reason: blockedManifestReason)
                    }
                }
            } else if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "sidebar.extensions.loading", defaultValue: "Loading sidebar extensions"))
                        .mosaicFont(size: 12)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
                .accessibilityIdentifier("MosaicExtensionSidebarEmptyState")
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .mosaicFont(size: 26, weight: .regular)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                        )
                    VStack(spacing: 6) {
                        Text(emptyStateTitle)
                            .mosaicFont(size: 14, weight: .semibold)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text(errorText ?? emptyStateDetail)
                            .mosaicFont(size: 12)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if disabledExtensionCount > 0 || unapprovedExtensionCount > 0 {
                            Text(extensionAvailabilityDetail)
                                .mosaicFont(size: 12)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    extensionEmptyActions()
                        .padding(.top, 2)
                }
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
                .accessibilityIdentifier("MosaicExtensionSidebarEmptyState")
            }
        }
        .task {
            xpcHost.update(snapshotProvider: snapshotProvider, actionHandler: actionHandler)
            await observeExtensionAvailability()
        }
        .onChange(of: snapshotProvider().sequence) { _, _ in
            xpcHost.sendSnapshotDidChange()
        }
        .onChange(of: snapshotUpdateToken) { _, _ in
            xpcHost.sendSnapshotDidChange()
        }
        .onDisappear {
            xpcHost.invalidate()
        }
        .sheet(isPresented: $isShowingAccessReview) {
            if let identity, let effectiveGrant {
                accessReviewSheet(identity: identity, effectiveGrant: effectiveGrant)
            }
        }
    }

    private func observeExtensionAvailability() async {
        isLoading = true
        errorText = nil
        do {
            try await observeIdentitySequence(
                extensionPointIdentifier: MosaicSidebarExtensionPoint.identifier()
            )
        } catch {
            identity = nil
            xpcHost.invalidate()
            blockedManifestReason = nil
            isLoading = false
            errorText = String(
                localized: "sidebar.extensions.error",
                defaultValue: "Mosaic could not load sidebar extensions."
            )
        }
    }

    private var emptyStateTitle: String {
        if enabledIdentities.count > 1 {
            return String(localized: "sidebar.extensions.choose.title", defaultValue: "Choose a sidebar extension")
        }
        return String(localized: "sidebar.extensions.empty.title", defaultValue: "No sidebar extension enabled")
    }

    private var emptyStateDetail: String {
        if enabledIdentities.count > 1 {
            return String(
                localized: "sidebar.extensions.choose.detail",
                defaultValue: "Choose which enabled extension should replace the sidebar."
            )
        }
        return String(
            localized: "sidebar.extensions.empty.detail",
            defaultValue: "Install and enable a Mosaic sidebar extension to show it here."
        )
    }

    private var extensionAvailabilityDetail: String {
        if unapprovedExtensionCount > 0 {
            return String(
                localized: "sidebar.extensions.unapproved.detail",
                defaultValue: "An installed sidebar extension needs approval before Mosaic can use it."
            )
        }
        return String(
            localized: "sidebar.extensions.disabled.detail",
            defaultValue: "A sidebar extension is installed but disabled."
        )
    }

    @ViewBuilder
    private func extensionEmptyActions() -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                extensionEmptyActionButtons()
            }
            VStack(spacing: 8) {
                extensionEmptyActionButtons()
            }
        }
    }

    @ViewBuilder
    private func extensionEmptyActionButtons() -> some View {
        if enabledIdentities.count > 1 {
            Menu {
                ForEach(enabledIdentities, id: \.bundleIdentifier) { enabledIdentity in
                    TrackedButton("mosaicinstalledextensionsidebarhostview_button_344", action: {
                        selectExtension(enabledIdentity)
                    }) {
                        Label(enabledIdentity.localizedName, systemImage: "puzzlepiece.extension")
                    }
                }
            } label: {
                Label(
                    String(localized: "sidebar.extensions.choose.action", defaultValue: "Choose Extension"),
                    systemImage: "puzzlepiece.extension"
                )
            }
            .menuStyle(.button)
            .controlSize(.small)
        }

        TrackedButton("mosaicinstalledextensionsidebarhostview_button_360", action: {
            presentExtensionBrowser()
        }) {
            Label(
                String(localized: "sidebar.extensions.manage.short", defaultValue: "Manage"),
                systemImage: "puzzlepiece.extension"
            )
        }
        .controlSize(.small)

        TrackedButton("mosaicinstalledextensionsidebarhostview_button_370", action: {
            onUseDefaultSidebar()
        }) {
            Label(
                String(localized: "sidebar.extensions.useDefault.short", defaultValue: "Use Default"),
                systemImage: "sidebar.left"
            )
        }
        .controlSize(.small)
    }

    private func extensionControlStrip(activeIdentity: AppExtensionIdentity?) -> some View {
        HStack(spacing: 8) {
            extensionIdentityControl(activeIdentity: activeIdentity)
            Spacer(minLength: 8)
            if effectiveGrant?.needsAdditionalApproval == true {
                TrackedButton("mosaicinstalledextensionsidebarhostview_button_386", action: {
                    isShowingAccessReview = true
                }) {
                    Label(
                        String(localized: "sidebar.extensions.access.statusLimited", defaultValue: "Limited"),
                        systemImage: "lock"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(String(localized: "sidebar.extensions.access.statusLimited.help", defaultValue: "This extension has limited access."))
            }
            TrackedButton("mosaicinstalledextensionsidebarhostview_button_398", action: {
                isShowingExtensionDetails = true
            }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help(String(localized: "sidebar.extensions.details.help", defaultValue: "Show extension details"))
            .popover(isPresented: $isShowingExtensionDetails, arrowEdge: .top) {
                extensionDetailsPopover(activeIdentity: activeIdentity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, SidebarWorkspaceScrollInsets.workspaceList.top + 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TitlebarControlAnchorView { browserAnchorView = $0 })
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.86))
    }

    private func extensionDetailsPopover(activeIdentity: AppExtensionIdentity?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .mosaicFont(size: 18, weight: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeIdentity?.localizedName ?? String(localized: "sidebar.provider.extensions.title", defaultValue: "Extension Sidebar"))
                        .mosaicFont(size: 13, weight: .semibold)
                        .lineLimit(1)
                    Text(String(localized: "sidebar.extensions.details.runtime", defaultValue: "Secure extension connection"))
                        .mosaicFont(size: 11)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                detailRow(
                    title: String(localized: "sidebar.extensions.details.status", defaultValue: "Status"),
                    value: blockedManifestReason.map(blockedStatusText(reason:)) ?? (activeIdentity == nil
                        ? String(localized: "sidebar.extensions.details.statusWaiting", defaultValue: "Waiting for an enabled extension")
                        : String(localized: "sidebar.extensions.details.statusActive", defaultValue: "Connected"))
                )
                if let activeIdentity {
                    detailRow(
                        title: String(localized: "sidebar.extensions.details.bundle", defaultValue: "Bundle"),
                        value: activeIdentity.bundleIdentifier
                    )
                }
                if let manifest = effectiveGrant?.manifest {
                    detailRow(
                        title: String(localized: "sidebar.extensions.details.manifest", defaultValue: "Configuration"),
                        value: "\(manifest.id) · API \(manifest.minimumAPIVersion.major).\(manifest.minimumAPIVersion.minor)"
                    )
                }
            }

            if let effectiveGrant {
                Divider()
                permissionSection(effectiveGrant: effectiveGrant)
            } else if let blockedManifestReason {
                Divider()
                Text(blockedDetailText(reason: blockedManifestReason))
                    .mosaicFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let activeIdentity, let effectiveGrant {
                    HStack(spacing: 8) {
                        TrackedButton("mosaicinstalledextensionsidebarhostview_button_470", String(localized: "sidebar.extensions.access.review", defaultValue: "Review Access...")) {
                            isShowingAccessReview = true
                        }
                        .controlSize(.small)
                        .disabled(!effectiveGrant.needsAdditionalApproval)

                        TrackedButton("mosaicinstalledextensionsidebarhostview_button_476", String(localized: "sidebar.extensions.access.keepLimited", defaultValue: "Keep Limited")) {
                            xpcHost.revokeSensitiveAccess(bundleIdentifier: activeIdentity.bundleIdentifier)
                            self.effectiveGrant = xpcHost.currentEffectiveGrant
                            xpcHost.sendSnapshotDidChange()
                        }
                        .controlSize(.small)
                        .disabled(!effectiveGrant.hasSensitiveAccess)
                    }
                }
                HStack(spacing: 8) {
                    TrackedButton("mosaicinstalledextensionsidebarhostview_button_486", String(localized: "sidebar.extensions.manage.short", defaultValue: "Manage")) {
                        isShowingExtensionDetails = false
                        presentExtensionBrowser()
                    }
                    .controlSize(.small)
                    TrackedButton("mosaicinstalledextensionsidebarhostview_button_491", String(localized: "sidebar.extensions.useDefault.short", defaultValue: "Use Default")) {
                        isShowingExtensionDetails = false
                        onUseDefaultSidebar()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func blockedExtensionView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .mosaicFont(size: 20, weight: .regular)
                .foregroundStyle(.secondary)
            Text(String(localized: "sidebar.extensions.blocked.title", defaultValue: "Extension Blocked"))
                .mosaicFont(size: 13, weight: .semibold)
            Text(blockedDetailText(reason: reason))
                .mosaicFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    blockedExtensionActionButtons()
                }
                VStack(alignment: .leading, spacing: 8) {
                    blockedExtensionActionButtons()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("MosaicExtensionSidebarBlockedState")
    }

    @ViewBuilder
    private func blockedExtensionActionButtons() -> some View {
        TrackedButton("mosaicinstalledextensionsidebarhostview_button_531", action: {
            blockedManifestReason = nil
            effectiveGrant = nil
            xpcHost.invalidate()
            hostReloadToken &+= 1
        }) {
            Label(
                String(localized: "sidebar.extensions.retry", defaultValue: "Try Again"),
                systemImage: "arrow.clockwise"
            )
        }
        .controlSize(.small)

        TrackedButton("mosaicinstalledextensionsidebarhostview_button_544", action: {
            onUseDefaultSidebar()
        }) {
            Label(
                String(localized: "sidebar.extensions.useDefault.short", defaultValue: "Use Default"),
                systemImage: "sidebar.left"
            )
        }
        .controlSize(.small)

        TrackedButton("mosaicinstalledextensionsidebarhostview_button_554", action: {
            presentExtensionBrowser()
        }) {
            Label(
                String(localized: "sidebar.extensions.manage.short", defaultValue: "Manage"),
                systemImage: "puzzlepiece.extension")
        }
        .controlSize(.small)
    }

    private func blockedStatusText(reason: String) -> String {
        switch reason {
        case "connectionInterrupted":
            return String(localized: "sidebar.extensions.blocked.status.connectionInterrupted", defaultValue: "Blocked, connection interrupted")
        case "manifestTimedOut":
            return String(localized: "sidebar.extensions.blocked.status.manifestTimedOut", defaultValue: "Blocked, configuration timed out")
        case "missingManifest":
            return String(localized: "sidebar.extensions.blocked.status.missingManifest", defaultValue: "Blocked, missing configuration")
        case "invalidManifest":
            return String(localized: "sidebar.extensions.blocked.status.invalidManifest", defaultValue: "Blocked, invalid configuration")
        default:
            return String(localized: "sidebar.extensions.blocked.status.failedManifest", defaultValue: "Blocked, configuration unavailable")
        }
    }

    private func blockedDetailText(reason: String) -> String {
        switch reason {
        case "connectionInterrupted":
            return String(localized: "sidebar.extensions.blocked.detail.connectionInterrupted", defaultValue: "Mosaic lost the extension connection. No workspace data or actions are being shared.")
        case "manifestTimedOut":
            return String(localized: "sidebar.extensions.blocked.detail.manifestTimedOut", defaultValue: "Mosaic did not receive this extension's configuration in time. No workspace data or actions are being shared.")
        case "missingManifest":
            return String(localized: "sidebar.extensions.blocked.detail.missingManifest", defaultValue: "Mosaic did not receive a sidebar extension configuration, so no workspace data or actions were shared.")
        case "invalidManifest":
            return String(localized: "sidebar.extensions.blocked.detail.invalidManifest", defaultValue: "Mosaic rejected this extension's configuration. No workspace data or actions were shared.")
        default:
            return String(localized: "sidebar.extensions.blocked.detail.failedManifest", defaultValue: "Mosaic could not load this extension's configuration. No workspace data or actions were shared.")
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .mosaicFont(size: 11, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .mosaicFont(size: 11)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func permissionSection(effectiveGrant: MosaicSidebarExtensionEffectiveGrant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "sidebar.extensions.details.permissions", defaultValue: "Permissions"))
                .mosaicFont(size: 12, weight: .semibold)
            ForEach(effectiveGrant.manifest.readScopes, id: \.self) { scope in
                permissionRow(
                    title: scope.displayName,
                    detail: permissionDescription(scope: scope),
                    isGranted: effectiveGrant.readScopes.contains(scope)
                )
            }
            ForEach(effectiveGrant.manifest.actionScopes, id: \.self) { scope in
                permissionRow(
                    title: scope.displayName,
                    detail: permissionDescription(actionScope: scope),
                    isGranted: effectiveGrant.actionScopes.contains(scope)
                )
            }
        }
    }

    private func permissionRow(title: String, detail: String, isGranted: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .mosaicFont(size: 11, weight: .medium)
                .foregroundStyle(isGranted ? .green : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .mosaicFont(size: 11, weight: .medium)
                Text(detail)
                    .mosaicFont(size: 10)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(isGranted
                ? String(localized: "sidebar.extensions.details.granted", defaultValue: "Granted")
                : String(localized: "sidebar.extensions.details.pending", defaultValue: "Pending"))
                .mosaicFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func extensionIdentityControl(activeIdentity: AppExtensionIdentity?) -> some View {
        if enabledIdentities.count > 1 {
            Menu {
                ForEach(enabledIdentities, id: \.bundleIdentifier) { enabledIdentity in
                    TrackedButton("mosaicinstalledextensionsidebarhostview_button_657", action: {
                        selectExtension(enabledIdentity)
                    }) {
                        Label(
                            enabledIdentity.localizedName,
                            systemImage: enabledIdentity.bundleIdentifier == activeIdentity?.bundleIdentifier ? "checkmark" : "puzzlepiece.extension"
                        )
                    }
                }
            } label: {
                Label(
                    activeIdentity?.localizedName ?? String(localized: "sidebar.provider.extensions.title", defaultValue: "Extension Sidebar"),
                    systemImage: "puzzlepiece.extension"
                )
                .lineLimit(1)
            }
            .menuStyle(.button)
            .controlSize(.small)
        } else {
            Label(
                activeIdentity?.localizedName ?? String(localized: "sidebar.provider.extensions.title", defaultValue: "Extension Sidebar"),
                systemImage: "puzzlepiece.extension"
            )
            .mosaicFont(size: 12, weight: .semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func presentExtensionBrowser() {
        guard let anchorView = browserAnchorView
            ?? NSApp.keyWindow?.contentView
            ?? NSApp.mainWindow?.contentView else { return }
        AppDelegate.shared?.openSidebarExtensionBrowser(
            from: anchorView,
            title: String(
                localized: "sidebar.extensions.browser.title",
                defaultValue: "Sidebar Extensions"
            )
        )
    }

    private func extensionAccessBanner(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "sidebar.extensions.access.title", defaultValue: "Limited extension access"))
                .mosaicFont(size: 12, weight: .semibold)
                .foregroundStyle(.primary)
            Text(String.localizedStringWithFormat(
                String(localized: "sidebar.extensions.access.detail", defaultValue: "%@ will not receive workspace data or run actions until you grant its requested access."),
                effectiveGrant.manifest.displayName
            ))
            .mosaicFont(size: 11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pendingPermissionDescriptions(effectiveGrant: effectiveGrant), id: \.self) { description in
                    Label(description, systemImage: "circle")
                        .mosaicFont(size: 11)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    limitedAccessActionButtons(identity: identity, effectiveGrant: effectiveGrant)
                }
                VStack(alignment: .leading, spacing: 8) {
                    limitedAccessActionButtons(identity: identity, effectiveGrant: effectiveGrant)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.88))
    }

    @ViewBuilder
    private func limitedAccessActionButtons(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> some View {
        TrackedButton("mosaicinstalledextensionsidebarhostview_button_743", action: {
            isShowingAccessReview = true
        }) {
            Text(String(localized: "sidebar.extensions.access.review", defaultValue: "Review Access..."))
        }
        .controlSize(.small)
        TrackedButton("mosaicinstalledextensionsidebarhostview_button_749", action: {
            keepLimitedAccess(identity: identity, effectiveGrant: effectiveGrant)
        }) {
            Text(String(localized: "sidebar.extensions.access.keepLimited", defaultValue: "Keep Limited"))
        }
        .controlSize(.small)
    }

    private func accessReviewSheet(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .mosaicFont(size: 22, weight: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "sidebar.extensions.access.review.title", defaultValue: "Review access for %@"),
                        effectiveGrant.manifest.displayName
                    ))
                    .mosaicFont(size: 15, weight: .semibold)
                    Text(identity.bundleIdentifier)
                        .mosaicFont(size: 11)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text(String(localized: "sidebar.extensions.access.review.detail", defaultValue: "Mosaic will only share the following data and actions if you allow this request."))
                .mosaicFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                detailRow(
                    title: String(localized: "sidebar.extensions.details.manifest", defaultValue: "Configuration"),
                    value: "\(effectiveGrant.manifest.id) · API \(effectiveGrant.manifest.minimumAPIVersion.major).\(effectiveGrant.manifest.minimumAPIVersion.minor)"
                )
                Divider()
                permissionSection(effectiveGrant: effectiveGrant)
            }

            HStack(spacing: 8) {
                Spacer()
                TrackedButton("mosaicinstalledextensionsidebarhostview_button_794", String(localized: "sidebar.extensions.access.keepLimited", defaultValue: "Keep Limited")) {
                    keepLimitedAccess(identity: identity, effectiveGrant: effectiveGrant)
                    isShowingAccessReview = false
                }
                .keyboardShortcut(.cancelAction)
                TrackedButton("mosaicinstalledextensionsidebarhostview_button_799", String(localized: "sidebar.extensions.access.allow", defaultValue: "Allow Requested Access")) {
                    grantRequestedAccess(identity: identity, effectiveGrant: effectiveGrant)
                    isShowingAccessReview = false
                }
                .buttonStyle(.mosaicAccent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420, alignment: .leading)
    }

    private func shouldShowAccessBanner(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> Bool {
        effectiveGrant.needsAdditionalApproval && !keptLimitedManifestKeys.contains(limitedChoiceKey(identity: identity, effectiveGrant: effectiveGrant))
    }

    private func grantRequestedAccess(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) {
        let key = limitedChoiceKey(identity: identity, effectiveGrant: effectiveGrant)
        keptLimitedManifestKeys.remove(key)
        MosaicSidebarExtensionLimitedChoiceStore().remove(key)
        xpcHost.grantRequestedAccess(bundleIdentifier: identity.bundleIdentifier)
        self.effectiveGrant = xpcHost.currentEffectiveGrant
        xpcHost.sendSnapshotDidChange()
    }

    private func keepLimitedAccess(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) {
        let key = limitedChoiceKey(identity: identity, effectiveGrant: effectiveGrant)
        keptLimitedManifestKeys.insert(key)
        MosaicSidebarExtensionLimitedChoiceStore().insert(key)
        xpcHost.revokeSensitiveAccess(bundleIdentifier: identity.bundleIdentifier)
        self.effectiveGrant = xpcHost.currentEffectiveGrant
        xpcHost.sendSnapshotDidChange()
    }

    private func limitedChoiceKey(
        identity: AppExtensionIdentity,
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> String {
        let readScopes = effectiveGrant.manifest.readScopes.map(\.rawValue).sorted().joined(separator: ",")
        let actionScopes = effectiveGrant.manifest.actionScopes.map(\.rawValue).sorted().joined(separator: ",")
        return "\(identity.bundleIdentifier)|\(effectiveGrant.manifest.id)|\(effectiveGrant.manifest.minimumAPIVersion.major).\(effectiveGrant.manifest.minimumAPIVersion.minor)|\(readScopes)|\(actionScopes)"
    }

    private func pendingPermissionDescriptions(
        effectiveGrant: MosaicSidebarExtensionEffectiveGrant
    ) -> [String] {
        let pendingReadScopes = effectiveGrant.manifest.readScopes.filter {
            !effectiveGrant.readScopes.contains($0)
        }
        let pendingActionScopes = effectiveGrant.manifest.actionScopes.filter {
            !effectiveGrant.actionScopes.contains($0)
        }
        return pendingReadScopes.map(permissionDescription(scope:)) +
            pendingActionScopes.map(permissionDescription(actionScope:))
    }

    private func permissionDescription(scope: MosaicExtensionScope) -> String {
        switch scope {
        case .workspaceList:
            return String(localized: "sidebar.extensions.permission.workspaceList.detail", defaultValue: "Read workspace IDs and names")
        case .workspaceMetadata:
            return String(localized: "sidebar.extensions.permission.workspaceMetadata.detail", defaultValue: "Read workspace names, branches, unread counts, and selection")
        case .surfaceMetadata:
            return String(localized: "sidebar.extensions.permission.surfaceMetadata.detail", defaultValue: "Read surfaces nested inside each workspace")
        case .workspacePaths:
            return String(localized: "sidebar.extensions.permission.workspacePaths.detail", defaultValue: "Read local workspace and project paths")
        case .notifications:
            return String(localized: "sidebar.extensions.permission.notifications.detail", defaultValue: "Read latest workspace notifications")
        case .networkPorts:
            return String(localized: "sidebar.extensions.permission.networkPorts.detail", defaultValue: "Read listening ports for each workspace")
        case .pullRequests:
            return String(localized: "sidebar.extensions.permission.pullRequests.detail", defaultValue: "Read pull request links associated with workspaces")
        }
    }

    private func permissionDescription(actionScope: MosaicExtensionActionScope) -> String {
        switch actionScope {
        case .createWorkspace:
            return String(localized: "sidebar.extensions.permission.createWorkspace.detail", defaultValue: "Create workspaces")
        case .selectWorkspace:
            return String(localized: "sidebar.extensions.permission.selectWorkspace.detail", defaultValue: "Select a workspace when you click in the extension")
        case .closeWorkspace:
            return String(localized: "sidebar.extensions.permission.closeWorkspace.detail", defaultValue: "Close workspaces from the extension")
        case .createSurface:
            return String(localized: "sidebar.extensions.permission.createSurface.detail", defaultValue: "Create terminal and browser surfaces")
        case .selectSurface:
            return String(localized: "sidebar.extensions.permission.selectSurface.detail", defaultValue: "Select surfaces inside a workspace")
        case .closeSurface:
            return String(localized: "sidebar.extensions.permission.closeSurface.detail", defaultValue: "Close surfaces inside a workspace")
        case .splitSurface:
            return String(localized: "sidebar.extensions.permission.splitSurface.detail", defaultValue: "Create split surfaces")
        case .zoomSurface:
            return String(localized: "sidebar.extensions.permission.zoomSurface.detail", defaultValue: "Toggle surface zoom")
        case .navigateWorkspace:
            return String(localized: "sidebar.extensions.permission.navigateWorkspace.detail", defaultValue: "Navigate between workspaces")
        case .navigateSurface:
            return String(localized: "sidebar.extensions.permission.navigateSurface.detail", defaultValue: "Navigate between surfaces")
        case .openURL:
            return String(localized: "sidebar.extensions.permission.openURL.detail", defaultValue: "Open links from the extension")
        case .createWorkspaceWithPath:
            return String(localized: "sidebar.extensions.permission.createWorkspaceWithPath.detail", defaultValue: "Create workspaces for specific local folders")
        }
    }

    private func observeIdentitySequence(extensionPointIdentifier: String) async throws {
        var identities = try AppExtensionIdentity.matching(appExtensionPointIDs: extensionPointIdentifier)
            .makeAsyncIterator()
        let availabilityTask = Task {
            var availabilityUpdates = AppExtensionIdentity.availabilityUpdates.makeAsyncIterator()
            while !Task.isCancelled {
                guard let availability = await availabilityUpdates.next() else { break }
                disabledExtensionCount = availability.disabledCount
                unapprovedExtensionCount = availability.unapprovedCount
            }
        }
        defer {
            availabilityTask.cancel()
        }
        while !Task.isCancelled {
            guard let update = await identities.next() else { break }
            applyEnabledExtensionIdentities(update)
        }
    }

    private func applyEnabledExtensionIdentities(_ identities: [AppExtensionIdentity]) {
        let sortedIdentities = deduplicatedExtensionIdentities(identities)
        enabledIdentities = sortedIdentities
        let nextIdentity: AppExtensionIdentity?
        if let selectedExtensionBundleID,
           let selectedIdentity = sortedIdentities.first(where: { $0.bundleIdentifier == selectedExtensionBundleID }) {
            nextIdentity = selectedIdentity
        } else if selectedExtensionBundleID == nil, sortedIdentities.count == 1 {
            nextIdentity = sortedIdentities[0]
            selectedExtensionBundleID = nextIdentity?.bundleIdentifier
            UserDefaults.standard.set(nextIdentity?.bundleIdentifier, forKey: Self.selectedExtensionBundleIDDefaultsKey)
        } else {
            nextIdentity = nil
        }
        updateSelectedExtensionName(nextIdentity)
        if nextIdentity?.bundleIdentifier != identity?.bundleIdentifier {
            xpcHost.invalidate()
            effectiveGrant = nil
            identity = nextIdentity
        }
        isLoading = false
        errorText = nil
    }

    private func deduplicatedExtensionIdentities(_ identities: [AppExtensionIdentity]) -> [AppExtensionIdentity] {
        let sortedIdentities = identities.sorted {
            if $0.localizedName == $1.localizedName {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return $0.localizedName < $1.localizedName
        }
        var seenBundleIdentifiers = Set<String>()
        return sortedIdentities.filter { identity in
            seenBundleIdentifiers.insert(identity.bundleIdentifier).inserted
        }
    }

    private func selectExtension(_ selectedIdentity: AppExtensionIdentity) {
        selectedExtensionBundleID = selectedIdentity.bundleIdentifier
        UserDefaults.standard.set(selectedIdentity.bundleIdentifier, forKey: Self.selectedExtensionBundleIDDefaultsKey)
        UserDefaults.standard.set(selectedIdentity.localizedName, forKey: Self.selectedExtensionNameDefaultsKey)
        applyEnabledExtensionIdentities(enabledIdentities)
    }

    private func updateSelectedExtensionName(_ selectedIdentity: AppExtensionIdentity?) {
        if let selectedIdentity {
            UserDefaults.standard.set(selectedIdentity.localizedName, forKey: Self.selectedExtensionNameDefaultsKey)
        } else if selectedExtensionBundleID == nil {
            UserDefaults.standard.removeObject(forKey: Self.selectedExtensionNameDefaultsKey)
        }
    }

}

private extension MosaicExtensionScope {
    var displayName: String {
        switch self {
        case .workspaceList:
            return String(localized: "sidebar.extensions.scope.workspaceList", defaultValue: "Workspace list")
        case .workspaceMetadata:
            return String(localized: "sidebar.extensions.scope.workspaceMetadata", defaultValue: "Workspace metadata")
        case .surfaceMetadata:
            return String(localized: "sidebar.extensions.scope.surfaceMetadata", defaultValue: "Surface metadata")
        case .workspacePaths:
            return String(localized: "sidebar.extensions.scope.workspacePaths", defaultValue: "Workspace paths")
        case .notifications:
            return String(localized: "sidebar.extensions.scope.notifications", defaultValue: "Notifications")
        case .networkPorts:
            return String(localized: "sidebar.extensions.scope.networkPorts", defaultValue: "Network ports")
        case .pullRequests:
            return String(localized: "sidebar.extensions.scope.pullRequests", defaultValue: "Pull requests")
        }
    }
}

private extension MosaicExtensionActionScope {
    var displayName: String {
        switch self {
        case .createWorkspace:
            return String(localized: "sidebar.extensions.actionScope.createWorkspace", defaultValue: "Create workspaces")
        case .selectWorkspace:
            return String(localized: "sidebar.extensions.actionScope.selectWorkspace", defaultValue: "Select workspaces")
        case .closeWorkspace:
            return String(localized: "sidebar.extensions.actionScope.closeWorkspace", defaultValue: "Close workspaces")
        case .createSurface:
            return String(localized: "sidebar.extensions.actionScope.createSurface", defaultValue: "Create surfaces")
        case .selectSurface:
            return String(localized: "sidebar.extensions.actionScope.selectSurface", defaultValue: "Select surfaces")
        case .closeSurface:
            return String(localized: "sidebar.extensions.actionScope.closeSurface", defaultValue: "Close surfaces")
        case .splitSurface:
            return String(localized: "sidebar.extensions.actionScope.splitSurface", defaultValue: "Split surfaces")
        case .zoomSurface:
            return String(localized: "sidebar.extensions.actionScope.zoomSurface", defaultValue: "Zoom surfaces")
        case .navigateWorkspace:
            return String(localized: "sidebar.extensions.actionScope.navigateWorkspace", defaultValue: "Navigate workspaces")
        case .navigateSurface:
            return String(localized: "sidebar.extensions.actionScope.navigateSurface", defaultValue: "Navigate surfaces")
        case .openURL:
            return String(localized: "sidebar.extensions.actionScope.openURL", defaultValue: "Open URLs")
        case .createWorkspaceWithPath:
            return String(localized: "sidebar.extensions.actionScope.createWorkspaceWithPath", defaultValue: "Create workspaces with paths")
        }
    }
}

@MainActor
private final class MosaicSidebarExtensionHostXPC {
    private static let untrustedScopes: Set<MosaicExtensionScope> = []
    private static let untrustedActionScopes: Set<MosaicExtensionActionScope> = []
    private static let manifestRequestTimeoutNanoseconds: UInt64 = 5_000_000_000

    private var connection: NSXPCConnection?
    private var extensionProxy: MosaicSidebarExtensionXPC?
    private var exportedObject: MosaicSidebarHostXPCObject?
    private var snapshotProvider: (() -> MosaicSidebarSnapshot)?
    private var actionHandler: ((MosaicSidebarAction) -> MosaicSidebarActionResult)?
    private var allowedScopes = untrustedScopes
    private var allowedActionScopes = untrustedActionScopes
    private var connectionGeneration: UInt64 = 0
    private var bundleIdentifier: String?
    private var currentManifest: MosaicExtensionManifest?
    private var onGrantChanged: ((MosaicSidebarExtensionEffectiveGrant?) -> Void)?
    private var onManifestBlocked: ((String?) -> Void)?
    private var awaitingManifestGeneration: UInt64?
    private var manifestRequestTimeoutTask: Task<Void, Never>?
    private let grantStore = MosaicSidebarExtensionGrantStore()

    var currentEffectiveGrant: MosaicSidebarExtensionEffectiveGrant? {
        guard let bundleIdentifier, let currentManifest else { return nil }
        return grantStore.effectiveGrant(bundleIdentifier: bundleIdentifier, manifest: currentManifest)
    }

    func update(
        snapshotProvider: @escaping @MainActor () -> MosaicSidebarSnapshot,
        actionHandler: @escaping @MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult
    ) {
        self.snapshotProvider = snapshotProvider
        self.actionHandler = actionHandler
        exportedObject?.actionHandler = scopedActionHandler(actionHandler)
        updateExportedSnapshotFilter()
    }

    func attach(
        connection: NSXPCConnection,
        bundleIdentifier: String,
        snapshotProvider: @escaping @MainActor () -> MosaicSidebarSnapshot,
        actionHandler: @escaping @MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult,
        onGrantChanged: @escaping @MainActor (MosaicSidebarExtensionEffectiveGrant?) -> Void,
        onManifestBlocked: @escaping @MainActor (String?) -> Void
    ) {
        invalidate()
        connectionGeneration += 1
        let generation = connectionGeneration
        let exportedObject = MosaicSidebarHostXPCObject(
            snapshotProvider: { Self.untrustedSnapshot(from: snapshotProvider()) },
            actionHandler: scopedActionHandler(actionHandler),
            onAcceptedAction: { [weak self] in
                self?.sendSnapshotDidChange()
            },
            isCurrentGeneration: { [weak self] in
                self?.connectionGeneration == generation
            }
        )
        connection.exportedInterface = NSXPCInterface(with: MosaicSidebarHostXPC.self)
        connection.exportedObject = exportedObject
        connection.remoteObjectInterface = NSXPCInterface(with: MosaicSidebarExtensionXPC.self)
        connection.invalidationHandler = { [weak self, generation] in
            Task { @MainActor in
                self?.clearConnection(ifCurrentGeneration: generation)
            }
        }
        connection.interruptionHandler = { [weak self, generation] in
            Task { @MainActor in
                self?.clearProxy(ifCurrentGeneration: generation)
            }
        }
        self.exportedObject = exportedObject
        self.snapshotProvider = snapshotProvider
        self.actionHandler = actionHandler
        self.connection = connection
        self.bundleIdentifier = bundleIdentifier
        self.currentManifest = nil
        self.onGrantChanged = onGrantChanged
        self.onManifestBlocked = onManifestBlocked
        self.allowedScopes = Self.untrustedScopes
        self.allowedActionScopes = Self.untrustedActionScopes
        self.extensionProxy = connection.remoteObjectProxy as? MosaicSidebarExtensionXPC
        connection.resume()
        requestManifestThenSendInitialSnapshot(generation: generation)
    }

    func sendSnapshotDidChange() {
        guard let extensionProxy, let snapshotProvider else { return }
        do {
            extensionProxy.sidebarSnapshotDidChange(try MosaicSidebarXPCCodec.encodeSnapshot(filteredSnapshot(from: snapshotProvider)))
        } catch {
#if DEBUG
            mosaicDebugLog("extension.sidebar.xpc.snapshot.encode.failed error=\(error.localizedDescription)")
#endif
        }
    }

    func invalidate() {
        connectionGeneration += 1
        let generation = connectionGeneration
        connection?.invalidate()
        clearConnection(ifCurrentGeneration: generation)
    }

    private func clearProxy(ifCurrentGeneration generation: UInt64) {
        guard connectionGeneration == generation else { return }
        extensionProxy = nil
        cancelManifestRequestTimeout()
        blockUntrustedExtension(reason: "connectionInterrupted")
        updateExportedSnapshotFilter()
    }

    private func clearConnection(ifCurrentGeneration generation: UInt64) {
        guard connectionGeneration == generation else { return }
        cancelManifestRequestTimeout()
        connection = nil
        extensionProxy = nil
        exportedObject = nil
        allowedScopes = Self.untrustedScopes
        allowedActionScopes = Self.untrustedActionScopes
        bundleIdentifier = nil
        currentManifest = nil
        onGrantChanged?(nil)
        onGrantChanged = nil
        onManifestBlocked?(nil)
        onManifestBlocked = nil
    }

    private func requestManifestThenSendInitialSnapshot(generation: UInt64) {
        guard let extensionProxy,
              let requestExtensionManifest = extensionProxy.requestExtensionManifest else {
            blockUntrustedExtension(reason: "missingManifest")
            updateExportedSnapshotFilter()
            return
        }
        beginManifestRequestTimeout(generation: generation)
        requestExtensionManifest { [weak self] payload, error in
            Task { @MainActor [generation] in
                guard let self else { return }
                guard self.connectionGeneration == generation else { return }
                guard self.awaitingManifestGeneration == generation else { return }
                self.cancelManifestRequestTimeout()
                if let payload {
                    do {
                        let manifest = try MosaicSidebarXPCCodec.decodeManifest(payload)
                        try validateSidebarManifest(manifest)
                        self.applyManifest(manifest)
                    } catch {
                        self.blockUntrustedExtension(reason: "invalidManifest")
#if DEBUG
                        mosaicDebugLog("extension.sidebar.manifest.invalid error=\(error.localizedDescription)")
#endif
                    }
                } else {
                    self.blockUntrustedExtension(reason: "manifestRequestFailed")
                    if let error {
#if DEBUG
                        mosaicDebugLog("extension.sidebar.manifest.failed error=\(error)")
#endif
                    }
                }
                self.updateExportedSnapshotFilter()
                if self.currentEffectiveGrant?.needsAdditionalApproval == false {
                    self.sendSnapshotDidChange()
                }
            }
        }
    }

    private func beginManifestRequestTimeout(generation: UInt64) {
        cancelManifestRequestTimeout()
        awaitingManifestGeneration = generation
        manifestRequestTimeoutTask = Task { @MainActor [weak self, generation] in
            do {
                try await Task.sleep(nanoseconds: Self.manifestRequestTimeoutNanoseconds)
            } catch {
                return
            }
            guard let self,
                  self.connectionGeneration == generation,
                  self.awaitingManifestGeneration == generation else { return }
            self.cancelManifestRequestTimeout()
            self.blockUntrustedExtension(reason: "manifestTimedOut")
            self.updateExportedSnapshotFilter()
        }
    }

    private func cancelManifestRequestTimeout() {
        awaitingManifestGeneration = nil
        manifestRequestTimeoutTask?.cancel()
        manifestRequestTimeoutTask = nil
    }

    func grantRequestedAccess(bundleIdentifier: String) {
        guard self.bundleIdentifier == bundleIdentifier, let currentManifest else { return }
        grantStore.grantRequestedAccess(bundleIdentifier: bundleIdentifier, manifest: currentManifest)
        applyManifest(currentManifest)
        sendSnapshotDidChange()
    }

    func revokeSensitiveAccess(bundleIdentifier: String) {
        guard self.bundleIdentifier == bundleIdentifier, let currentManifest else { return }
        grantStore.revokeSensitiveAccess(bundleIdentifier: bundleIdentifier, manifest: currentManifest)
        applyManifest(currentManifest)
        sendSnapshotDidChange()
    }

    private func applyManifest(_ manifest: MosaicExtensionManifest) {
        cancelManifestRequestTimeout()
        currentManifest = manifest
        guard let bundleIdentifier else {
            allowedScopes = Self.untrustedScopes
            allowedActionScopes = Self.untrustedActionScopes
            onGrantChanged?(nil)
            return
        }
        let effectiveGrant = grantStore.effectiveGrant(bundleIdentifier: bundleIdentifier, manifest: manifest)
        allowedScopes = effectiveGrant.readScopes
        allowedActionScopes = effectiveGrant.actionScopes
        onManifestBlocked?(nil)
        onGrantChanged?(effectiveGrant)
    }

    private func filteredSnapshot(from snapshotProvider: () -> MosaicSidebarSnapshot) -> MosaicSidebarSnapshot {
        snapshotProvider().filtered(for: allowedScopes, actionScopes: allowedActionScopes)
    }

    private func updateExportedSnapshotFilter() {
        guard let snapshotProvider else { return }
        exportedObject?.snapshotProvider = { [weak self] in
            guard let self else {
                return Self.untrustedSnapshot(from: snapshotProvider())
            }
            return filteredSnapshot(from: snapshotProvider)
        }
    }

    private func scopedActionHandler(
        _ actionHandler: @escaping @MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult
    ) -> (@MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult) {
        { [weak self] action in
            guard let self,
                  self.currentManifest != nil,
                  self.allowedActionScopes.isSuperset(of: action.requiredScopes) else {
                return MosaicSidebarActionResult(
                    accepted: false,
                    message: String(localized: "sidebar.extensions.action.scopeRejected", defaultValue: "Extension action is not granted")
                )
            }
            return actionHandler(action)
        }
    }

    private func blockUntrustedExtension(reason: String) {
        cancelManifestRequestTimeout()
        allowedScopes = Self.untrustedScopes
        allowedActionScopes = Self.untrustedActionScopes
        currentManifest = nil
        onGrantChanged?(nil)
        onManifestBlocked?(reason)
#if DEBUG
        mosaicDebugLog("extension.sidebar.manifest.blocked reason=\(reason)")
#endif
    }

    private static func untrustedSnapshot(from snapshot: MosaicSidebarSnapshot) -> MosaicSidebarSnapshot {
        MosaicSidebarSnapshot(
            apiVersion: snapshot.apiVersion,
            sequence: snapshot.sequence,
            selectedWorkspaceID: nil,
            workspaces: []
        )
    }
}

private final class MosaicSidebarHostXPCObject: NSObject, MosaicSidebarHostXPC {
    @MainActor var snapshotProvider: () -> MosaicSidebarSnapshot
    @MainActor var actionHandler: (MosaicSidebarAction) -> MosaicSidebarActionResult
    @MainActor var onAcceptedAction: () -> Void
    @MainActor var isCurrentGeneration: () -> Bool

    @MainActor
    init(
        snapshotProvider: @escaping @MainActor () -> MosaicSidebarSnapshot,
        actionHandler: @escaping @MainActor (MosaicSidebarAction) -> MosaicSidebarActionResult,
        onAcceptedAction: @escaping @MainActor () -> Void,
        isCurrentGeneration: @escaping @MainActor () -> Bool
    ) {
        self.snapshotProvider = snapshotProvider
        self.actionHandler = actionHandler
        self.onAcceptedAction = onAcceptedAction
        self.isCurrentGeneration = isCurrentGeneration
    }

    func requestSidebarSnapshot(reply: @escaping (NSData?, NSString?) -> Void) {
        Task { @MainActor in
            guard isCurrentGeneration() else {
                reply(nil, String(localized: "sidebar.extensions.action.staleConnection", defaultValue: "Extension connection is no longer active") as NSString)
                return
            }
            do {
                reply(try MosaicSidebarXPCCodec.encodeSnapshot(snapshotProvider()), nil)
            } catch {
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }

    func performSidebarAction(_ payload: NSData, reply: @escaping (NSData?, NSString?) -> Void) {
        Task { @MainActor in
            guard isCurrentGeneration() else {
                reply(nil, String(localized: "sidebar.extensions.action.staleConnection", defaultValue: "Extension connection is no longer active") as NSString)
                return
            }
            do {
                let action = try MosaicSidebarXPCCodec.decodeAction(payload)
                let result = actionHandler(action)
                reply(try MosaicSidebarXPCCodec.encodeActionResult(result), nil)
                if result.accepted {
                    onAcceptedAction()
                }
            } catch {
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }
}
