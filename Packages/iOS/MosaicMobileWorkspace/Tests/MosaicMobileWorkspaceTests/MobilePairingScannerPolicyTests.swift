import Testing
@testable import MosaicMobileWorkspace

/// The pairing scanner accepts any mosaic channel's pairing scheme (`mosaic-ios://`
/// for release, `mosaic-ios-dev://` for development). This guards the predicate
/// the UI hands to the camera service so a generic QR code (a URL, a Wi-Fi join
/// code) can never be mistaken for a pairing link, while cross-channel pairing
/// from inside the app still works.
@Suite struct MobilePairingScannerPolicyTests {
    @Test(arguments: [
        ("mosaic-ios://attach?ticket=abc", true),
        ("mosaic-ios://", true),
        ("mosaic-ios-dev://attach?v=2&r=100.64.0.5:58465", true),
        ("mosaic-ios-dev://", true),
        ("https://example.com", false),
        ("WIFI:S:net;;", false),
        ("", false),
    ])
    func acceptsOnlyPairingLinks(code: String, expected: Bool) {
        #expect(MobilePairingScannerPolicy.acceptsCode(code) == expected)
    }
}
