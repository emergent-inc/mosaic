import SwiftUI

#if DEBUG
struct AgentSessionDebugMenuButtons: View {
    let openReact: () -> Void
    let openSolid: () -> Void

    var body: some View {
        TrackedButton("agentsessiondebugmenubuttons_button_9", 
            String(
                localized: "debug.menu.openAgentGuiReact",
                defaultValue: "Open Agent GUI (React)"
            )
        ) {
            openReact()
        }

        TrackedButton("agentsessiondebugmenubuttons_button_18", 
            String(
                localized: "debug.menu.openAgentGuiSolid",
                defaultValue: "Open Agent GUI (Solid)"
            )
        ) {
            openSolid()
        }
    }
}
#endif
