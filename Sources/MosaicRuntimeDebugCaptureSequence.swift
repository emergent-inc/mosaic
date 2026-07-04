import Foundation

actor MosaicRuntimeDebugCaptureSequence {
    private var sequence = 0

    func next() -> Int {
        sequence += 1
        return sequence
    }
}
