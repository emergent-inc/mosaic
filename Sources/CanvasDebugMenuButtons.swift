#if DEBUG
import SwiftUI

struct CanvasDebugMenuButtons: View {
    let workspace: Workspace?
    let openStressWorkspacesWithLoadedSurfaces: () -> Void

    var body: some View {
        TrackedButton("canvasdebugmenubuttons_button_9", 
            String(
                localized: "debug.menu.openStressWorkspacesWithLoadedSurfaces",
                defaultValue: "Open Stress Workspaces and Load All Terminals"
            )
        ) {
            openStressWorkspacesWithLoadedSurfaces()
        }

        TrackedButton("canvasdebugmenubuttons_button_18", 
            String(
                localized: "debug.menu.showCanvasCommandScrollHint",
                defaultValue: "Show Canvas Scroll Hint"
            )
        ) {
            guard let workspace else { return }
            _ = debugShowCanvasCommandScrollHint(in: workspace)
        }
        .disabled(workspace?.layoutMode != .canvas)
    }
}
#endif
