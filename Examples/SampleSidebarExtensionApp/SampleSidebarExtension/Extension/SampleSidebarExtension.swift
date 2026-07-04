import MosaicExtensionKit
import SwiftUI

@main
final class SampleSidebarExtension: @MainActor MosaicSidebarExtension {
    static let manifest = MosaicExtensionManifest(
        id: "co.emergent.inc.MosaicExtKitSampleSidebarApp.Extension",
        displayName: String(localized: "sampleSidebar.manifest.displayName", defaultValue: "MOSAIC Sample Sidebar Extension"),
        readScopes: [
            .workspaceList,
            .workspaceMetadata,
            .surfaceMetadata,
            .notifications,
            .networkPorts,
            .pullRequests,
        ],
        actionScopes: [
            .createSurface,
            .selectWorkspace,
            .selectSurface,
            .navigateWorkspace,
            .navigateSurface,
        ]
    )

    private let model = SidebarConnectionModel()

    required init() {}

    var body: some View {
        SampleSidebarView(model: model)
    }

    func update(context: MosaicSidebarContext) {
        model.update(context: context)
    }

    func connectionStatusDidChange(_ status: MosaicSidebarConnectionStatus) {
        model.connectionStatusDidChange(status)
    }
}
