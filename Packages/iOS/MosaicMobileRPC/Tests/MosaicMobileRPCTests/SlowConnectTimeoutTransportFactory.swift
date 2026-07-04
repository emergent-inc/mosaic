import MosaicMobileCore
@testable import MosaicMobileRPC

struct SlowConnectTimeoutTransportFactory: CmxByteTransportFactory {
    let transport: SlowConnectTimeoutTransport

    func makeTransport(for route: CmxAttachRoute) throws -> any CmxByteTransport {
        transport
    }
}
