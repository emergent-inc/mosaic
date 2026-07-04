#if DEBUG
import MosaicDebugLog

@inline(__always)
func mosaicDebugLog(_ message: @autoclosure () -> String) {
    MosaicDebugLog.logDebugEvent(message())
}
#endif
