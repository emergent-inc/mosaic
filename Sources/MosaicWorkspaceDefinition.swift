import Foundation

struct MosaicWorkspaceDefinition: Codable, Sendable {
    var name: String?
    var cwd: String?
    var color: String?
    /// User-defined environment variables inherited by every shell spawned in the
    /// workspace (issue #5995). Managed `MOSAIC_*` variables always win.
    var env: [String: String]?
    var layout: MosaicLayoutNode?

    init(
        name: String? = nil,
        cwd: String? = nil,
        color: String? = nil,
        env: [String: String]? = nil,
        layout: MosaicLayoutNode? = nil
    ) {
        self.name = name
        self.cwd = cwd
        self.color = color
        self.env = env
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        layout = try container.decodeIfPresent(MosaicLayoutNode.self, forKey: .layout)

        if let rawColor = try container.decodeIfPresent(String.self, forKey: .color) {
            let defaults = decoder.userInfo[.mosaicWorkspaceColorDefaults] as? UserDefaults ?? .standard
            guard let normalized = WorkspaceTabColorSettings.resolvedColorHex(rawColor, defaults: defaults) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .color,
                    in: container,
                    debugDescription: "Invalid color \"\(rawColor)\". Expected 6-digit hex format (#RRGGBB) or a workspace color name"
                )
            }
            color = normalized
        } else {
            color = nil
        }
    }
}
