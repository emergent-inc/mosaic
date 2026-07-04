import Foundation
import Testing
@testable import MosaicMobileCore

/// The pairing/attach URL scheme is channel-specific so the system Camera app
/// can never hand a beta/prod QR to a dev build that also claimed the scheme:
/// dev (Debug/tagged) builds register + emit `mosaic-ios-dev`, Release (beta +
/// prod) registers + emits `mosaic-ios`. Parsers accept every channel's scheme so
/// cross-channel pairing still works from inside the app.
@Suite struct CmxPairingURLSchemeTests {
    @Test func developmentBuildsEmitDevScheme() {
        #expect(CmxPairingURLScheme.scheme(isDevelopmentBuild: true) == "mosaic-ios-dev")
    }

    @Test func releaseBuildsEmitReleaseScheme() {
        #expect(CmxPairingURLScheme.scheme(isDevelopmentBuild: false) == "mosaic-ios")
    }

    @Test func currentMatchesThisBuildsCompileChannel() {
        // `current` derives from the DEBUG compile flag, so a Debug test run
        // emits the dev scheme and a Release test run emits the release scheme.
        #if DEBUG
        #expect(CmxPairingURLScheme.current == "mosaic-ios-dev")
        #else
        #expect(CmxPairingURLScheme.current == "mosaic-ios")
        #endif
    }

    @Test func parserAcceptsEverySchemeRegardlessOfChannel() {
        // Both channels' schemes parse, case-insensitively, so a phone on
        // either channel can pair from a QR minted by either channel's Mac.
        #expect(CmxPairingURLScheme.isPairingScheme("mosaic-ios"))
        #expect(CmxPairingURLScheme.isPairingScheme("mosaic-ios-dev"))
        #expect(CmxPairingURLScheme.isPairingScheme("MOSAIC-IOS-DEV"))
    }

    @Test func parserRejectsForeignSchemes() {
        #expect(!CmxPairingURLScheme.isPairingScheme(nil))
        #expect(!CmxPairingURLScheme.isPairingScheme(""))
        #expect(!CmxPairingURLScheme.isPairingScheme("https"))
        // A different mosaic scheme that is not a pairing scheme must not match.
        #expect(!CmxPairingURLScheme.isPairingScheme("mosaic-ios-staging"))
    }

    @Test func prefixCheckAcceptsBothChannelsAndRejectsOthers() {
        #expect(CmxPairingURLScheme.hasPairingScheme("mosaic-ios://attach?v=2&r=100.64.0.5:58465"))
        #expect(CmxPairingURLScheme.hasPairingScheme("mosaic-ios-dev://attach?v=2&r=100.64.0.5:58465"))
        #expect(CmxPairingURLScheme.hasPairingScheme("MOSAIC-IOS://attach?v=2"))
        #expect(!CmxPairingURLScheme.hasPairingScheme("https://example.com"))
        // A bare scheme name without "://" is not a deep link.
        #expect(!CmxPairingURLScheme.hasPairingScheme("mosaic-ios"))
    }
}
