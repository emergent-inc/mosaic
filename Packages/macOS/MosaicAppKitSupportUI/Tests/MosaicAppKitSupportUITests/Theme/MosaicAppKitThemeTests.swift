import AppKit
import MosaicFoundation
import Testing

@testable import MosaicAppKitSupportUI

@MainActor
@Suite struct MosaicAppKitThemeTests {
    @Test func buttonBackgroundColorMatchesHex() {
        #expect(MosaicAppKitTheme.buttonBackgroundHex == "#2170FF")
        #expect(MosaicAppKitTheme.buttonBackgroundColor.hexString() == "#2170FF")
    }

    @Test func applyButtonStyleSetsBorderedBlueBackgroundAndWhiteTitle() {
        let button = NSButton(title: "Continue", target: nil, action: nil)
        button.isBordered = false
        button.isTransparent = true

        MosaicAppKitTheme.applyButtonStyle(to: button)

        #expect(button.isBordered)
        #expect(button.isTransparent == false)
        #expect(button.bezelColor == MosaicAppKitTheme.buttonBackgroundColor)
        #expect(button.contentTintColor == MosaicAppKitTheme.textColor)

        let foreground = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(foreground == MosaicAppKitTheme.textColor)
    }

    @Test func applyTextStyleSetsWhiteForeground() {
        let textField = NSTextField(labelWithString: "Label")
        textField.textColor = .secondaryLabelColor

        MosaicAppKitTheme.applyTextStyle(to: textField)

        #expect(textField.textColor == MosaicAppKitTheme.textColor)
    }

    @Test func applyTextStylePreservesClearHiddenFields() {
        let hiddenField = NSTextField(string: "")
        hiddenField.textColor = .clear

        MosaicAppKitTheme.applyTextStyle(to: hiddenField)

        #expect(hiddenField.textColor == .clear)
    }

    @Test func applyRecursivelyStylesNestedControls() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let label = NSTextField(labelWithString: "Status")
        label.textColor = .labelColor
        let button = NSButton(title: "OK", target: nil, action: nil)
        container.addSubview(label)
        container.addSubview(button)

        MosaicAppKitTheme.applyRecursively(to: container)

        #expect(label.textColor == MosaicAppKitTheme.textColor)
        #expect(button.bezelColor == MosaicAppKitTheme.buttonBackgroundColor)
        #expect(button.contentTintColor == MosaicAppKitTheme.textColor)
    }
}
