import AppKit
import Foundation

extension BrowserPanel {
    func downloadRenderedPDFDocument() {
        guard let url = renderedPDFDocumentURL else {
            NSSound.beep()
            return
        }
        guard let webView = webView as? MosaicWebView else {
            NSSound.beep()
            return
        }
        let traceID = MosaicWebView.makeContextDownloadTraceID(prefix: "pdfdl")
        webView.downloadURLViaSession(
            url,
            suggestedFilename: nil,
            sender: nil,
            fallbackAction: nil,
            fallbackTarget: nil,
            traceID: traceID
        )
    }

    func printRenderedPDFDocument() {
        guard renderedPDFDocumentURL != nil else {
            NSSound.beep()
            return
        }
        webView.mosaicRunPrintOperation()
    }
}
