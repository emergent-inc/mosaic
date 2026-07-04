import AppKit

extension NSScreen {
    var mosaicDisplayID: UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = deviceDescription[key] as? NSNumber else { return nil }
        return value.uint32Value
    }
}
