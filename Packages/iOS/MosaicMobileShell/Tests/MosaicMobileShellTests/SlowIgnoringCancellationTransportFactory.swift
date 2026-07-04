import MosaicMobileCore
import MosaicMobileRPC

struct SlowIgnoringCancellationTransportFactory: CmxByteTransportFactory {
    func makeTransport(for route: CmxAttachRoute) throws -> any CmxByteTransport {
        SlowIgnoringCancellationTransport()
    }
}
