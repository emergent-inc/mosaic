import MosaicAgentLaunch
import XCTest

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

final class RovoDevHookConfigTests: XCTestCase {
    func testInstallAddsRootBlockAndUninstallRestoresOriginalConfig() {
        let existing = """
        sessions:
          persistenceDir: /tmp/rovo

        """

        let installed = RovoDevHookConfig.installing(events: Self.events, in: existing)

        XCTAssertTrue(installed.contains("# mosaic hooks rovodev begin"))
        XCTAssertTrue(installed.contains("eventHooks:"))
        XCTAssertTrue(installed.contains("  events:"))
        XCTAssertTrue(installed.contains("    - name: on_complete"))
        XCTAssertTrue(installed.contains("    - command: \"mosaic hooks rovodev stop\""))
        XCTAssertEqual(RovoDevHookConfig.uninstalling(from: installed), existing)
    }

    func testInstallMergesIntoExistingEventsAndIsIdempotent() {
        let existing = """
        eventHooks:
          events:
            - name: user_hook
              commands:
                - command: "echo user"

        """

        let installed = RovoDevHookConfig.installing(events: Self.events, in: existing)
        let reinstalled = RovoDevHookConfig.installing(events: Self.events, in: installed)

        XCTAssertEqual(reinstalled, installed)
        XCTAssertTrue(installed.contains("    # mosaic hooks rovodev begin"))
        XCTAssertTrue(installed.contains("    - name: user_hook"))
        XCTAssertTrue(installed.contains("        - command: \"echo user\""))
        XCTAssertTrue(installed.contains("    - name: on_tool_permission"))
        XCTAssertEqual(RovoDevHookConfig.uninstalling(from: installed), existing)
    }

    func testInstallAddsEventsChildWhenOnlyEventHooksRootExists() {
        let existing = """
        eventHooks:
          enabled: true

        """

        let installed = RovoDevHookConfig.installing(events: Self.events, in: existing)

        XCTAssertTrue(installed.contains("eventHooks:\n  # mosaic hooks rovodev begin\n  events:"))
        XCTAssertTrue(installed.contains("  enabled: true"))
        XCTAssertEqual(RovoDevHookConfig.uninstalling(from: installed), existing)
    }

    func testInstallIgnoresNestedEventsThatAreNotDirectEventHooksChildren() {
        let existing = """
        eventHooks:
          nested:
            events:
              - name: user_hook
                commands:
                  - command: "echo user"

        """

        let installed = RovoDevHookConfig.installing(events: Self.events, in: existing)

        XCTAssertTrue(installed.contains("eventHooks:\n  # mosaic hooks rovodev begin\n  events:"))
        XCTAssertTrue(installed.contains("    events:\n      - name: user_hook"))
        XCTAssertEqual(RovoDevHookConfig.uninstalling(from: installed), existing)
    }

    func testInstallEscapesCommandStringsForYaml() {
        let events = [
            RovoDevHookConfig.Event(
                name: "on_complete",
                command: "mosaic hooks rovodev stop --message \"done\" \\ next\nline"
            )
        ]

        let installed = RovoDevHookConfig.installing(events: events, in: "")

        XCTAssertTrue(installed.contains("command: \"mosaic hooks rovodev stop --message \\\"done\\\" \\\\ next\\nline\""))
    }

    func testUninstallLeavesDanglingMarkedBlockUntouched() {
        let existing = """
        eventHooks:
          events:
            # mosaic hooks rovodev begin
            - name: on_complete
              commands:
                - command: "mosaic hooks rovodev stop"
        sessions:
          persistenceDir: /tmp/rovo

        """

        XCTAssertEqual(RovoDevHookConfig.uninstalling(from: existing), existing)
    }

    private static let events = [
        RovoDevHookConfig.Event(name: "on_complete", command: "mosaic hooks rovodev stop"),
        RovoDevHookConfig.Event(name: "on_error", command: "mosaic hooks rovodev stop"),
        RovoDevHookConfig.Event(name: "on_tool_permission", command: "mosaic hooks rovodev prompt-submit"),
    ]
}
