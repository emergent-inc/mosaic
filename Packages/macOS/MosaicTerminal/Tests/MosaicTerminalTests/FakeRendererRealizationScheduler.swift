@testable import MosaicTerminal

final class FakeRendererRealizationScheduler: TerminalRendererRealizationScheduling {
    @MainActor
    func scheduleImmediatePass() {}
}
