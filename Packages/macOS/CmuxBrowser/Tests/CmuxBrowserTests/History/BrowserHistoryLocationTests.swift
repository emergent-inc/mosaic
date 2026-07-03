import Foundation
import Testing
@testable import CmuxBrowser

@Suite struct BrowserHistoryLocationTests {
    @Test func foldsDebugAndStagingNamespaces() {
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "mosaic.com.emergent.app.debug.my-tag") == "mosaic.com.emergent.app.debug")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "mosaic.com.emergent.app.staging.rc") == "mosaic.com.emergent.app.staging")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "mosaic.com.emergent.app") == "mosaic.com.emergent.app")
    }

    @Test func historyFileURLNestsUnderNamespace() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let location = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "mosaic.com.emergent.app.debug.tag")
        #expect(location.namespace == "mosaic.com.emergent.app.debug")
        #expect(location.historyFileURL.path == "/tmp/appsupport/mosaic.com.emergent.app.debug/browser_history.json")
    }

    @Test func legacyURLPresentOnlyWhenNamespaceDiffers() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let tagged = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "mosaic.com.emergent.app.debug.tag")
        #expect(tagged.legacyTaggedHistoryFileURL?.path == "/tmp/appsupport/mosaic.com.emergent.app.debug.tag/browser_history.json")

        let prod = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "mosaic.com.emergent.app")
        #expect(prod.legacyTaggedHistoryFileURL == nil)
    }
}
