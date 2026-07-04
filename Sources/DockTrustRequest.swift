struct DockTrustRequest: Identifiable, Sendable {
    var id: String { descriptor.fingerprint }
    let descriptor: MosaicActionTrustDescriptor
    let configPath: String
}
