import MosaicMobileCore
@testable import MosaicMobileRPC

struct ResponseTimeoutSurvivalTransportFactory: CmxByteTransportFactory {
    let transport: ResponseTimeoutSurvivalTransport

    func makeTransport(for route: CmxAttachRoute) throws -> any CmxByteTransport {
        transport
    }
}
