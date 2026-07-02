import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct TabManagerAutomaticWelcomeTests {
    @Test
    @MainActor
    func automaticWelcomeIsDisabledEvenWhenWorkspaceWouldOtherwiseQualify() {
        #expect(TabManager.shouldSendAutomaticWelcome(
            autoWelcomeIfNeeded: true,
            select: true,
            startsWithTerminal: true,
            welcomeAlreadyShown: false
        ) == false)
    }

    @Test(arguments: [
        (autoWelcomeIfNeeded: false, select: true, startsWithTerminal: true, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: false, startsWithTerminal: true, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: true, startsWithTerminal: false, welcomeAlreadyShown: false),
        (autoWelcomeIfNeeded: true, select: true, startsWithTerminal: true, welcomeAlreadyShown: true),
    ])
    @MainActor
    func automaticWelcomeStaysDisabledForNonQualifyingWorkspaceInputs(
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
