import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

struct MenuBarProfilingLauncherTests {
    @Test
    func testMenuBarProfilingLaunchesCurrentProcessForFifteenSecondsWithoutOpeningOutput() {
        let arguments = MenuBarProfilingLauncher.arguments(pid: 1234)
        #expect(arguments == ["--pid", "1234", "--duration", "15"])
    }

    @Test
    func testMenuBarProfilingCanDeferSubmissionToProgressWindow() {
        let arguments = MenuBarProfilingLauncher.arguments(pid: 1234, submitProfile: false)
        #expect(arguments == ["--pid", "1234", "--duration", "15", "--no-submit"])
    }

    @Test
    func testMenuBarProfilingEstimatesDefaultCaptureSeconds() {
        #expect(MenuBarProfilingLauncher.estimatedCaptureSeconds() == 60)
    }
}
