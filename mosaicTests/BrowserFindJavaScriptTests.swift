import XCTest
import AppKit
import WebKit

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

// Find-in-page script generation and escaping moved into the MosaicBrowser package
// (BrowserFindScript). Its behavior is covered by MosaicBrowserTests/Find/BrowserFindServiceTests.

final class BrowserPopupDecisionTests: XCTestCase {
    func testLinkActivatedPlainLeftClickDoesNotCreatePopup() {
        XCTAssertFalse(
            browserNavigationShouldCreatePopup(
                navigationType: .linkActivated,
                modifierFlags: [],
                buttonNumber: 0
            )
        )
    }

    func testOtherNavigationWithPopupFeaturesCreatesPopup() {
        XCTAssertTrue(
            browserNavigationShouldCreatePopup(
                navigationType: .other,
                modifierFlags: [],
                buttonNumber: 0,
                popupFeaturesWereSpecified: true,
                currentEventType: .keyDown,
                currentEventButtonNumber: 0
            )
        )
    }

    func testOtherNavigationWithoutPopupFeaturesDoesNotCreatePopup() {
        XCTAssertFalse(
            browserNavigationShouldCreatePopup(
                navigationType: .other,
                modifierFlags: [],
                buttonNumber: 0
            )
        )
    }

    func testOtherNavigationMiddleClickDoesNotCreatePopup() {
        XCTAssertFalse(
            browserNavigationShouldCreatePopup(
                navigationType: .other,
                modifierFlags: [],
                buttonNumber: 2
            )
        )
    }

    func testLinkActivatedCmdClickDoesNotCreatePopup() {
        XCTAssertFalse(
            browserNavigationShouldCreatePopup(
                navigationType: .linkActivated,
                modifierFlags: [.command],
                buttonNumber: 0
            )
        )
    }

    func testPopupFeaturesAreAbsentWhenAllWindowFeaturesAreNil() {
        XCTAssertFalse(
            browserNavigationPopupFeaturesWereSpecified(
                x: nil,
                y: nil,
                width: nil,
                height: nil,
                menuBarVisibility: nil,
                statusBarVisibility: nil,
                toolbarsVisibility: nil,
                allowsResizing: nil
            )
        )
    }

    func testPopupFeaturesArePresentWhenWidthIsSpecified() {
        XCTAssertTrue(
            browserNavigationPopupFeaturesWereSpecified(
                x: nil,
                y: nil,
                width: NSNumber(value: 640),
                height: nil,
                menuBarVisibility: nil,
                statusBarVisibility: nil,
                toolbarsVisibility: nil,
                allowsResizing: nil
            )
        )
    }
}
