import Foundation
import Testing
import MosaicSidebarProviderKit

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

/// Regression coverage for the right-click sidebar-button view switcher.
///
/// v0.64.10 shipped seven built-in sidebar views — Default Workspaces plus the
/// Project Worktrees, Attention Queue, Dev Servers, Last Prompt, Super Compact,
/// and Browser Stack presets — that the sidebar-button context menu let users
/// switch between. #4994 ("Replace sidebar extension kit contract") swept that
/// menu behind the experimental Extensions beta flag and stubbed the built-in
/// providers out, so on a default install (beta off) the menu and every one of
/// its views disappeared (https://github.com/emergent-inc/mosaic/issues/5173).
///
/// These tests pin the two guarantees the regression broke: the built-in views
/// are available regardless of the experimental flag, and a selected view
/// resolves to itself (which is what drives the menu's active-view checkmark).
@MainActor
@Suite(.serialized)
struct SidebarProviderMenuRegressionTests {
    /// Stable ids of the seven built-in sidebar views, in menu order.
    private static let builtInViewIDs: [String] = [
        "mosaic.sidebar.default",
        "com.example.mosaic.sidebar.project-worktrees",
        "com.example.mosaic.sidebar.attention-queue",
        "com.example.mosaic.sidebar.dev-servers",
        "com.example.mosaic.sidebar.last-prompt",
        "com.example.mosaic.sidebar.super-compact",
        "com.example.mosaic.sidebar.browser-stack",
    ]

    private static let extensionsBetaKey = "extensions.beta.enabled"

    private func withExtensionsBeta(_ enabled: Bool, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.extensionsBetaKey)
        defaults.set(enabled, forKey: Self.extensionsBetaKey)
        defer { restore(previous, forKey: Self.extensionsBetaKey) }
        body()
    }

    private func withSelectedProvider(_ providerId: String, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let key = MosaicExtensionSidebarSelection.defaultsKey
        let previous = defaults.object(forKey: key)
        defaults.set(providerId, forKey: key)
        defer { restore(previous, forKey: key) }
        body()
    }

    private func restore(_ value: Any?, forKey key: String) {
        let defaults = UserDefaults.standard
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The built-in views must remain selectable even when the experimental
    /// Extensions beta is disabled — the regression hid every one of them.
    @Test
    func builtInViewsAvailableWhenExtensionsBetaDisabled() {
        withExtensionsBeta(false) {
            let availableIDs = Set(MosaicExtensionSidebarSelection.descriptors.map(\.id))
            for builtInID in Self.builtInViewIDs {
                #expect(
                    availableIDs.contains(builtInID),
                    "Built-in sidebar view \(builtInID) is missing from the switcher menu"
                )
            }
        }
    }

    /// Persisting a built-in view as the selection drives the menu's active-view
    /// checkmark to that view. This exercises the same path `showMenu` uses to
    /// decide which item is checked — read the persisted id from `UserDefaults`,
    /// resolve it through `effectiveProviderId`, then look up the descriptor —
    /// rather than asserting on the id in isolation.
    @Test
    func persistedBuiltInSelectionDrivesMenuCheckmark() {
        withExtensionsBeta(false) {
            for builtInID in Self.builtInViewIDs {
                withSelectedProvider(builtInID) {
                    let persisted = UserDefaults.standard.string(forKey: MosaicExtensionSidebarSelection.defaultsKey)
                        ?? MosaicExtensionSidebarSelection.defaultProviderId
                    let effective = MosaicExtensionSidebarSelection.effectiveProviderId(
                        persisted,
                        extensionsEnabled: MosaicExtensionSidebarSelection.isEnabled
                    )
                    let checkedID = MosaicExtensionSidebarSelection.descriptor(for: effective).id
                    #expect(
                        checkedID == builtInID,
                        "Persisted selection \(builtInID) did not drive the menu checkmark (got \(checkedID))"
                    )
                }
            }
        }
    }

    /// The hosted-extensions provider belongs to the experimental Extensions
    /// feature, so the effective selection (which the menu checkmark tracks)
    /// downgrades it to the default sidebar while the beta is off and honors it
    /// while the beta is on. Built-in views resolve to themselves either way —
    /// they are never gated by the flag.
    @Test
    func effectiveSelectionGatesHostedExtensionButNotBuiltInViews() {
        let projectWorktrees = "com.example.mosaic.sidebar.project-worktrees"
        #expect(
            MosaicExtensionSidebarSelection.effectiveProviderId(projectWorktrees, extensionsEnabled: false) == projectWorktrees
        )
        #expect(
            MosaicExtensionSidebarSelection.effectiveProviderId(projectWorktrees, extensionsEnabled: true) == projectWorktrees
        )

        let hosted = MosaicExtensionSidebarSelection.hostedExtensionsProviderId
        #expect(
            MosaicExtensionSidebarSelection.effectiveProviderId(hosted, extensionsEnabled: true) == hosted
        )
        #expect(
            MosaicExtensionSidebarSelection.effectiveProviderId(hosted, extensionsEnabled: false) == MosaicExtensionSidebarSelection.defaultProviderId
        )
    }

    /// The host renders the selected view through an
    /// `any MosaicSidebarProvider` existential
    /// (`MosaicExtensionSidebarSelection.provider(for:)?.render(snapshot:)`).
    /// `render(snapshot:)` must dynamic-dispatch to the concrete view; if it
    /// instead hits the empty protocol-extension default, every built-in view
    /// renders an empty sidebar even though the provider and workspaces are
    /// present — the second half of #5173. Super Compact lists every workspace
    /// in one section, so its rows must equal the workspace count.
    @Test
    func builtInProviderRendersRowsThroughHostExistential() {
        let snapshot = Self.populatedSnapshot(workspaceCount: 3)
        let provider = MosaicExtensionSidebarSelection.provider(for: "com.example.mosaic.sidebar.super-compact")
        #expect(provider != nil, "Super Compact provider should be registered")
        let model = provider?.render(snapshot: snapshot)
        #expect(
            (model?.sections.flatMap(\.rows).count ?? 0) == 3,
            "Selected view rendered no rows through the host existential (empty-sidebar regression)"
        )
    }

    /// `VerticalTabsSidebar.body` decides whether to show the default workspaces
    /// sidebar or an extension sidebar on every render. It used to do that with
    /// `descriptor(for:).id == defaultWorkspacesID`, which rebuilds the full
    /// `descriptors` list — constructing a `SettingCatalog` twice and scanning
    /// the custom-sidebars directory — on every body pass. That per-pass cost was
    /// the multiplier behind the sustained ~100% CPU re-render loop in #5970.
    /// `resolvesToDefaultSidebar(effectiveProviderId:)` is the cheap replacement;
    /// these tests pin that it routes identically to the old descriptor lookup
    /// for every effective selection.
    @Test
    func resolvesToDefaultSidebarMatchesDescriptorRoutingForBuiltInViews() {
        for betaEnabled in [false, true] {
            withExtensionsBeta(betaEnabled) {
                for builtInID in Self.builtInViewIDs {
                    let cheap = MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: builtInID)
                    let viaDescriptor = MosaicExtensionSidebarSelection.descriptor(for: builtInID).id
                        == MosaicSidebarProviderDescriptor.defaultWorkspacesID
                    #expect(
                        cheap == viaDescriptor,
                        "Routing mismatch for \(builtInID) (extensionsBeta=\(betaEnabled)): cheap=\(cheap) descriptor=\(viaDescriptor)"
                    )
                }
                // The default view routes to the workspaces sidebar; every bundled
                // preset routes to an extension sidebar.
                #expect(
                    MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(
                        effectiveProviderId: MosaicExtensionSidebarSelection.defaultProviderId
                    )
                )
                for presetID in Self.builtInViewIDs.dropFirst() {
                    #expect(
                        !MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: presetID),
                        "Bundled preset \(presetID) must route to an extension sidebar, not the default"
                    )
                }
            }
        }
    }

    /// The hosted-extensions provider only appears in `effectiveProviderId`'s
    /// output while the Extensions beta is on, and then it must route to an
    /// extension sidebar (not the default). Matches the descriptor lookup.
    @Test
    func resolvesToDefaultSidebarRoutesHostedExtensionToExtensionSidebar() {
        withExtensionsBeta(true) {
            let hosted = MosaicExtensionSidebarSelection.hostedExtensionsProviderId
            #expect(!MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: hosted))
            #expect(
                MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: hosted)
                    == (MosaicExtensionSidebarSelection.descriptor(for: hosted).id
                        == MosaicSidebarProviderDescriptor.defaultWorkspacesID)
            )
        }
    }

    /// An unknown/stale provider id (e.g. a deleted custom sidebar) has no
    /// renderable provider, so routing falls back to the default workspaces
    /// sidebar — exactly as `descriptor(for:)`'s `?? .defaultWorkspaces` did.
    @Test
    func resolvesToDefaultSidebarFallsBackForUnknownProvider() {
        withExtensionsBeta(true) {
            let unknown = "com.example.mosaic.sidebar.does-not-exist-\(UUID().uuidString)"
            #expect(MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: unknown))
            #expect(
                MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: unknown)
                    == (MosaicExtensionSidebarSelection.descriptor(for: unknown).id
                        == MosaicSidebarProviderDescriptor.defaultWorkspacesID)
            )

            // A custom-prefixed selection whose backing file does not exist also
            // falls back to the default sidebar.
            let missingCustom = MosaicExtensionSidebarSelection.customSidebarProviderPrefix
                + "missing-\(UUID().uuidString)"
            #expect(MosaicExtensionSidebarSelection.resolvesToDefaultSidebar(effectiveProviderId: missingCustom))
        }
    }

    /// Custom provider ids are persisted strings, so the fast path must keep the
    /// old descriptor enumeration boundary: only files directly inside the
    /// sidebars directory are renderable.
    @Test
    func customSidebarFileURLRejectsPathTraversalProviderIds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mosaic-custom-sidebar-test-\(UUID().uuidString)", isDirectory: true)
        let sidebarsDirectory = root.appendingPathComponent("sidebars", isDirectory: true)
        try FileManager.default.createDirectory(at: sidebarsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let validName = "valid-\(UUID().uuidString)"
        let validURL = sidebarsDirectory.appendingPathComponent("\(validName).swift", isDirectory: false)
        try Data().write(to: validURL)
        #expect(
            MosaicExtensionSidebarSelection.customSidebarFileURL(
                forProviderId: MosaicExtensionSidebarSelection.customSidebarProviderPrefix + validName,
                sidebarsDirectory: sidebarsDirectory
            ) == validURL
        )

        let escapedName = "outside-\(UUID().uuidString)"
        let escapedURL = root.appendingPathComponent("\(escapedName).swift", isDirectory: false)
        try Data().write(to: escapedURL)
        #expect(
            MosaicExtensionSidebarSelection.customSidebarFileURL(
                forProviderId: MosaicExtensionSidebarSelection.customSidebarProviderPrefix + "../\(escapedName)",
                sidebarsDirectory: sidebarsDirectory
            ) == nil
        )
    }

    private static func populatedSnapshot(workspaceCount: Int) -> MosaicSidebarProviderSnapshot {
        let workspaces = (0..<workspaceCount).map { index in
            MosaicSidebarProviderWorkspace(
                id: UUID(),
                title: "Workspace \(index)",
                customDescription: nil,
                isPinned: false,
                rootPath: "/tmp/ws\(index)",
                projectRootPath: "/tmp/ws\(index)",
                branchSummary: "main",
                remoteDisplayTarget: nil,
                remoteConnectionState: "disconnected",
                unreadCount: 0,
                latestNotificationText: nil,
                listeningPorts: []
            )
        }
        return MosaicSidebarProviderSnapshot(
            sequence: 1,
            selectedWorkspaceId: nil,
            workspaces: workspaces
        )
    }
}
