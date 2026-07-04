import MosaicSidebarProviderKit
import Foundation

public enum SidebarExamples {
    public static let providers: [any MosaicSidebarProvider] = [
        ProjectWorktreeSidebar(),
        AttentionQueueSidebar(),
        DevServerSidebar(),
        LastPromptSidebar(),
        SuperCompactSidebar(),
        BrowserStackSidebar(onAsyncStateLoaded: {
            BrowserStackSidebar.postStateDidLoadNotification()
        }),
    ]
}

struct ExampleSidebarSection {
    var id: String
    var title: MosaicSidebarProviderLocalizedText
    var systemImageName: String
    var projectRootPath: String?
    var workspaces: [MosaicSidebarProviderWorkspace]

    func render(
        rowTitle: (MosaicSidebarProviderWorkspace) -> String = { $0.title },
        accessory: MosaicSidebarProviderRowAccessory? = .inspector,
        subtitle: (MosaicSidebarProviderWorkspace) -> MosaicSidebarProviderText? = { _ in nil },
        trailingText: (MosaicSidebarProviderWorkspace) -> MosaicSidebarProviderText? = { _ in nil },
        leadingIcon: (MosaicSidebarProviderWorkspace) -> MosaicSidebarProviderIcon? = { _ in nil }
    ) -> MosaicSidebarProviderSection {
        MosaicSidebarProviderSection(
            id: id,
            treeSection: MosaicSidebarProviderTreeSection(
                id: id,
                title: title.defaultValue,
                titleText: title,
                subtitle: nil,
                systemImageName: systemImageName,
                projectRootPath: projectRootPath,
                workspaceIds: workspaces.map(\.id)
            ),
            rows: workspaces.map { workspace in
                MosaicSidebarProviderRow(
                    id: workspace.id,
                    title: rowTitle(workspace),
                    workspaceId: workspace.id,
                    accessory: accessory,
                    subtitle: subtitle(workspace),
                    trailingText: trailingText(workspace),
                    leadingIcon: leadingIcon(workspace)
                )
            }
        )
    }
}

func localized(_ key: String, _ defaultValue: String) -> MosaicSidebarProviderLocalizedText {
    MosaicSidebarProviderLocalizedText(key: key, defaultValue: defaultValue)
}

func renderModel(
    providerId: String,
    snapshot: MosaicSidebarProviderSnapshot,
    sections: [MosaicSidebarProviderSection],
    presentation: MosaicSidebarProviderPresentation = .tree
) -> MosaicSidebarProviderRenderModel {
    MosaicSidebarProviderRenderModel(
        providerId: providerId,
        snapshotSequence: snapshot.sequence,
        sections: presentation == .browserStack ? sections : sections.filter { !$0.rows.isEmpty },
        presentation: presentation
    )
}

func trimmed(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

func projectRoot(for workspace: MosaicSidebarProviderWorkspace) -> String? {
    trimmed(workspace.projectRootPath)
}

func displayName(for path: String) -> String {
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let name = url.lastPathComponent
    return name.isEmpty ? path : name
}
