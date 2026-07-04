import ExtensionFoundation
import ExtensionKit
import Foundation
import SwiftUI

struct MosaicSidebarExtensionScene<Extension: MosaicSidebarExtension>: AppExtensionScene {
    private let sidebarExtension: Extension
    private let id: String

    init(_ extension: Extension, id: String = MosaicSidebarExtensionPoint.defaultSceneID) {
        self.sidebarExtension = `extension`
        self.id = id
    }

    @MainActor
    var body: PrimitiveAppExtensionScene {
        let runtime = MosaicSidebarExtensionRuntime(sidebarExtension: sidebarExtension)
        let acceptConnection: @Sendable (NSXPCConnection) -> Bool = { connection in
            runtime.accept(connection)
        }
        return PrimitiveAppExtensionScene(id: id) {
            sidebarExtension.body
        } onConnection: { connection in
            acceptConnection(connection)
        }
    }
}
