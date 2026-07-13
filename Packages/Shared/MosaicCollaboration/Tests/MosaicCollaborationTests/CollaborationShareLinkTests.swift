import Foundation
import Testing
@testable import MosaicCollaboration

@Test func shareLinkUsesProductionSharingOriginByDefault() {
    let url = CollaborationShareLink.url(forSessionCode: "5ZNHGF9P", baseURLString: "https://sharing.mosaic.inc")
    #expect(url?.absoluteString == "https://sharing.mosaic.inc/s/5ZNHGF9P")
}

@Test func shareLinkTrimsWhitespaceAroundTheCode() {
    let url = CollaborationShareLink.url(forSessionCode: "  5ZNHGF9P\n", baseURLString: "https://sharing.mosaic.inc")
    #expect(url?.absoluteString == "https://sharing.mosaic.inc/s/5ZNHGF9P")
}

@Test func shareLinkRejectsEmptyCodes() {
    #expect(CollaborationShareLink.url(forSessionCode: "") == nil)
    #expect(CollaborationShareLink.url(forSessionCode: "   \n") == nil)
}

@Test func shareLinkHonorsBaseURLOverrideWithTrailingSlash() {
    let url = CollaborationShareLink.url(
        forSessionCode: "5ZNHGF9P",
        baseURLString: "http://localhost:3200/"
    )
    #expect(url?.absoluteString == "http://localhost:3200/s/5ZNHGF9P")
}

@Test func shareLinkDefaultBaseIsTheSharingDomain() {
    // Guards against accidental base changes: unless the environment override
    // is set, links must point at sharing.mosaic.inc.
    if ProcessInfo.processInfo.environment[CollaborationShareLink.baseURLEnvironmentKey] == nil {
        let url = CollaborationShareLink.url(forSessionCode: "ABCD")
        #expect(url?.absoluteString == "https://sharing.mosaic.inc/s/ABCD")
    }
}
