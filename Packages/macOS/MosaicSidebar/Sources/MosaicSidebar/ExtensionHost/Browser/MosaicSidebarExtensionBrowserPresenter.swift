public import AppKit
import ExtensionKit
import Foundation

@available(macOS 13.0, *)
@MainActor
@_spi(MosaicHostTransport)
public enum MosaicSidebarExtensionBrowserPresenter {
    public static func makeViewController(title: String) -> NSViewController {
        let browserViewController = EXAppExtensionBrowserViewController()
        browserViewController.title = title
        return browserViewController
    }
}
