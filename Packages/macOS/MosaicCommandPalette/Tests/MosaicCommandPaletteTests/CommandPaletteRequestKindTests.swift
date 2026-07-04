import Foundation
import Testing

@testable import MosaicCommandPalette

@Suite struct CommandPaletteRequestKindTests {
    @Test func notificationNamesMatchLegacyLiterals() {
        #expect(CommandPaletteRequestKind.commands.notificationName == "mosaic.commandPaletteRequested")
        #expect(CommandPaletteRequestKind.switcher.notificationName == "mosaic.commandPaletteSwitcherRequested")
        #expect(CommandPaletteRequestKind.renameTab.notificationName == "mosaic.commandPaletteRenameTabRequested")
        #expect(CommandPaletteRequestKind.renameWorkspace.notificationName == "mosaic.commandPaletteRenameWorkspaceRequested")
        #expect(
            CommandPaletteRequestKind.editWorkspaceDescription.notificationName
                == "mosaic.commandPaletteEditWorkspaceDescriptionRequested"
        )
    }

    @Test func everyKindMarksPending() {
        for kind in CommandPaletteRequestKind.allCases {
            #expect(kind.marksPending)
        }
    }

    @Test func notificationNamesAreDistinct() {
        let names = Set(CommandPaletteRequestKind.allCases.map(\.notificationName))
        #expect(names.count == CommandPaletteRequestKind.allCases.count)
    }
}
