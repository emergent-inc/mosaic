import Foundation
@testable import MosaicTerminal

final class FakeHibernationRecorder: AgentHibernationRecording {
    func recordTerminalInput(workspaceId: UUID, panelId: UUID) {}
}
