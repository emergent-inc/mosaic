import AppKit

@MainActor
private var mosaicBrowserWebKitKeyDownDispatchDepth = 0

@MainActor
func mosaicBrowserWebKitKeyDownDispatchIsActive() -> Bool {
    mosaicBrowserWebKitKeyDownDispatchDepth > 0
}

@MainActor
func mosaicWithBrowserWebKitKeyDownDispatch<T>(_ body: () -> T) -> T {
    mosaicBrowserWebKitKeyDownDispatchDepth += 1
    defer {
        mosaicBrowserWebKitKeyDownDispatchDepth = max(0, mosaicBrowserWebKitKeyDownDispatchDepth - 1)
    }
    return body()
}

@MainActor
extension MosaicWebView {
    func forwardKeyDownToWebKit(_ event: NSEvent) {
        mosaicWithBrowserWebKitKeyDownDispatch {
            super.keyDown(with: event)
        }
    }
}
