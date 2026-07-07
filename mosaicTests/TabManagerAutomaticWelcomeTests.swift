import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@Suite
struct TabManagerAutomaticWelcomeTests {
    @Test
    @MainActor
    func automaticWelcomeIsSentWhenWorkspaceQualifies() {
        #expect(TabManager.shouldSendAutomaticWelcome(
            autoWelcomeIfNeeded: true,
            select: true,
            startsWithTerminal: true,
            welcomeAlreadyShown: false
        ) == true)
    }

    @Test(arguments: [
        (autoWelcomeIfNeeded: false, select: true, startsWithTerminal: true, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: false, startsWithTerminal: true, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: true, startsWithTerminal: false, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: true, startsWithTerminal: true, welcomeAlreadyShown: true),
    ])
    @MainActor
    func automaticWelcomeIsSuppressedForNonQualifyingWorkspaceInputs(
        autoWelcomeIfNeeded: Bool,
        select: Bool,
        startsWithTerminal: Bool,
        welcomeAlreadyShown: Bool
    ) {
        #expect(TabManager.shouldSendAutomaticWelcome(
            autoWelcomeIfNeeded: autoWelcomeIfNeeded,
            select: select,
            startsWithTerminal: startsWithTerminal,
            welcomeAlreadyShown: welcomeAlreadyShown
        ) == false)
    }
}
