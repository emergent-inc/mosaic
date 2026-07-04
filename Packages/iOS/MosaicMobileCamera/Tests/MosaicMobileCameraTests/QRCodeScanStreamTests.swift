import Testing
@testable import MosaicMobileCamera

@Suite struct QRCodeScanStreamTests {
    @Test func yieldsCodesInOrderThenFinishes() async {
        let stream = QRCodeScanStream()
        stream.yield("mosaic-ios://one")
        stream.yield("mosaic-ios://two")
        stream.finish()

        var seen: [String] = []
        for await code in stream.codes {
            seen.append(code)
        }
        #expect(seen == ["mosaic-ios://one", "mosaic-ios://two"])
    }

    @Test func finishWithoutYieldProducesEmptySequence() async {
        let stream = QRCodeScanStream()
        stream.finish()

        var seen: [String] = []
        for await code in stream.codes {
            seen.append(code)
        }
        #expect(seen.isEmpty)
    }
}
