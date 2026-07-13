import Darwin
import Foundation
import SwiftUI

struct MosaicTaskManagerRow: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case window
        case workspace
        case tag
        case pane
        case terminalSurface
        case browserSurface
        case webview
        case process
        case programAggregate
        case codingAgentAggregate
        case childMemoryAggregate

        var systemImage: String {
            switch self {
            case .window: return "macwindow"
            case .workspace: return "rectangle.stack"
            case .tag: return "tag"
            case .pane: return "square.split.2x1"
            case .terminalSurface: return "terminal"
            case .browserSurface: return "globe"
            case .webview: return "network"
            case .process: return "gearshape"
            case .programAggregate: return "gearshape.2"
            case .codingAgentAggregate: return "sparkles"
            case .childMemoryAggregate: return "memorychip"
            }
        }

        var tint: Color {
            switch self {
            case .window: return .secondary
            case .workspace: return .accentColor
            case .tag: return .orange
            case .pane: return .secondary
            case .terminalSurface: return .green
            case .browserSurface: return .blue
            case .webview: return .purple
            case .process: return .secondary
            case .programAggregate: return .accentColor
            case .codingAgentAggregate: return .accentColor
            case .childMemoryAggregate: return .pink
            }
        }
    }

    let id: String
    let kind: Kind
    let level: Int
    let title: String
    let detail: String
    let resources: MosaicTaskManagerResources
    let isDimmed: Bool
    let workspaceId: UUID?
    let surfaceId: UUID?
    let terminalSurfaceId: UUID?
    let processId: Int?
    let rootProcessIds: [Int]
    let foregroundProcessGroupIds: [Int]
    let agentAssetName: String?

    /// Replaces the synthesized memberwise init so the PID arrays are
    /// stored in a canonical (deduped + ascending) order. The snapshot
    /// producers happen to sort today, but this guarantees the synthesized
    /// `Equatable` stays stable across reorderings so `.equatable()` keeps
    /// suppressing row re-renders even if a future producer forgets.
    /// Issue #4529.
    init(
        id: String,
        kind: Kind,
        level: Int,
        title: String,
        detail: String,
        resources: MosaicTaskManagerResources,
        isDimmed: Bool,
        workspaceId: UUID?,
        surfaceId: UUID?,
        terminalSurfaceId: UUID?,
        processId: Int?,
        rootProcessIds: [Int],
        foregroundProcessGroupIds: [Int],
        agentAssetName: String?
    ) {
        self.id = id
        self.kind = kind
        self.level = level
        self.title = title
        self.detail = detail
        self.resources = resources
        self.isDimmed = isDimmed
        self.workspaceId = workspaceId
        self.surfaceId = surfaceId
        self.terminalSurfaceId = terminalSurfaceId
        self.processId = processId
        self.rootProcessIds = Self.canonicalIds(rootProcessIds)
        self.foregroundProcessGroupIds = Self.canonicalIds(foregroundProcessGroupIds)
        self.agentAssetName = agentAssetName
    }

    private static func canonicalIds(_ ids: [Int]) -> [Int] {
        guard !ids.isEmpty else { return ids }
        return Array(Set(ids)).sorted()
    }

    var canViewWorkspace: Bool {
        workspaceId != nil
    }

    var canViewTerminal: Bool {
        workspaceId != nil && terminalSurfaceId != nil
    }

    var canKillProcess: Bool {
        !killableProcessIds.isEmpty
    }

    var killableProcessIds: [Int] {
        var ids = resources.processIds
        if let processId {
            ids.append(processId)
        }
        let currentPID = Int(getpid())
        return Array(Set(ids))
            .filter { $0 > 1 && $0 != currentPID }
            .sorted()
    }

    var gracefulProcessIds: [Int] {
        var ids = rootProcessIds
        if ids.isEmpty, let processId {
            ids.append(processId)
        }
        if ids.isEmpty {
            ids = resources.processIds
        }
        return safeProcessIds(ids)
    }

    var gracefulProcessGroupIds: [Int] {
        let currentProcessGroupId = Int(getpgrp())
        return Array(Set(foregroundProcessGroupIds))
            .filter { $0 > 1 && $0 != currentProcessGroupId }
            .sorted()
    }

    private func safeProcessIds(_ ids: [Int]) -> [Int] {
        let currentPID = Int(getpid())
        return Array(Set(ids))
            .filter { $0 > 1 && $0 != currentPID }
            .sorted()
    }

    func withAgentAssetName(_ assetName: String?) -> MosaicTaskManagerRow {
        guard agentAssetName != assetName else { return self }
        return MosaicTaskManagerRow(
            id: id,
            kind: kind,
            level: level,
            title: title,
            detail: detail,
            resources: resources,
            isDimmed: isDimmed,
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            terminalSurfaceId: terminalSurfaceId,
            processId: processId,
            rootProcessIds: rootProcessIds,
            foregroundProcessGroupIds: foregroundProcessGroupIds,
            agentAssetName: assetName
        )
    }
}

struct MosaicTaskManagerSortOrder: Equatable {
    enum Column: Equatable {
        case name
        case cpu
        case memory
        case processes

        var defaultDirection: Direction {
            switch self {
            case .name: return .ascending
            case .cpu, .memory, .processes: return .descending
            }
        }
    }

    enum Direction: Equatable {
        case ascending
        case descending

        var toggled: Direction {
            switch self {
            case .ascending: return .descending
            case .descending: return .ascending
            }
        }
    }

    static let defaultOrder = MosaicTaskManagerSortOrder(column: .cpu, direction: .descending)

    let column: Column
    let direction: Direction

    func toggled(for selectedColumn: Column) -> MosaicTaskManagerSortOrder {
        if selectedColumn == column {
            return MosaicTaskManagerSortOrder(column: column, direction: direction.toggled)
        }
        return MosaicTaskManagerSortOrder(
            column: selectedColumn,
            direction: selectedColumn.defaultDirection
        )
    }

    func sortedRows(_ rows: [MosaicTaskManagerRow]) -> [MosaicTaskManagerRow] {
        guard !rows.isEmpty else { return rows }
        var index = 0
        let rootLevel = rows.reduce(Int.max) { min($0, $1.level) }
        let nodes = parseNodes(rows, index: &index, level: rootLevel)
        return flatten(sortNodes(nodes))
    }

    private func parseNodes(
        _ rows: [MosaicTaskManagerRow],
        index: inout Int,
        level: Int
    ) -> [SortNode] {
        var nodes: [SortNode] = []
        while index < rows.count {
            let row = rows[index]
            if row.level < level {
                break
            }
            if row.level > level {
                break
            }

            index += 1
            var children: [SortNode] = []
            while index < rows.count, rows[index].level > row.level {
                children.append(contentsOf: parseNodes(rows, index: &index, level: rows[index].level))
            }
            nodes.append(SortNode(row: row, children: children))
        }
        return nodes
    }

    private func sortNodes(_ nodes: [SortNode]) -> [SortNode] {
        let sorted = nodes.enumerated().sorted { lhs, rhs in
            let comparison = compare(lhs.element.row, rhs.element.row)
            if comparison != .orderedSame {
                return direction == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            return lhs.offset < rhs.offset
        }

        return sorted.map { _, node in
            SortNode(row: node.row, children: sortNodes(node.children))
        }
    }

    private func flatten(_ nodes: [SortNode]) -> [MosaicTaskManagerRow] {
        nodes.flatMap { node in
            [node.row] + flatten(node.children)
        }
    }

    private func compare(_ lhs: MosaicTaskManagerRow, _ rhs: MosaicTaskManagerRow) -> ComparisonResult {
        switch column {
        case .name:
            return lhs.title.localizedStandardCompare(rhs.title)
        case .cpu:
            return valueComparison(lhs.resources.cpuPercent, rhs.resources.cpuPercent)
        case .memory:
            return valueComparison(lhs.resources.memoryBytes, rhs.resources.memoryBytes)
        case .processes:
            return valueComparison(lhs.resources.processCount, rhs.resources.processCount)
        }
    }

    private func valueComparison<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

private struct SortNode {
    let row: MosaicTaskManagerRow
    let children: [SortNode]
}

struct MosaicTaskManagerResources: Equatable {
    static let zero = MosaicTaskManagerResources(cpuPercent: 0, residentBytes: 0, processCount: 0)

    let cpuPercent: Double
    let memoryBytes: Int64
    let residentBytes: Int64
    let processCount: Int
    let processIds: [Int]

    init(
        cpuPercent: Double,
        residentBytes: Int64,
        memoryBytes: Int64? = nil,
        processCount: Int,
        processIds: [Int] = []
    ) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes ?? residentBytes
        self.residentBytes = residentBytes
        self.processCount = processCount
        self.processIds = Self.canonicalIds(processIds)
    }

    init(_ payload: [String: Any]) {
        self.cpuPercent = Self.double(payload["cpu_percent"])
        self.memoryBytes = Self.int64(payload["memory_bytes"] ?? payload["resident_bytes"])
        self.residentBytes = Self.int64(payload["resident_bytes"])
        self.processCount = Self.int(payload["process_count"]) ?? 0
        self.processIds = Self.canonicalIds(Self.intArray(payload["pids"]))
    }

    /// Canonical (deduped + ascending) ordering so synthesized
    /// `Equatable` stays stable across snapshot reorderings. See
    /// `MosaicTaskManagerRow.canonicalIds` for the same rationale.
    private static func canonicalIds(_ ids: [Int]) -> [Int] {
        guard !ids.isEmpty else { return ids }
        return Array(Set(ids)).sorted()
    }

    private static func double(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String,
           let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return 0
    }

    private static func int64(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String,
           let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return 0
    }

    private static func int(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func intArray(_ raw: Any?) -> [Int] {
        if let values = raw as? [Int] { return values }
        guard let values = raw as? [Any] else { return [] }
        return values.compactMap(int)
    }
}

struct MosaicTaskManagerMemoryDiagnostic: Sendable {
    let summary: String
    let appFootprintBytes: Int64
    let appResidentBytes: Int64
    let childRSSBytes: Int64
    let childProcessCount: Int
    let groups: [MosaicTaskManagerMemoryGroup]

    init?(_ payload: [String: Any]?) {
        guard let payload else { return nil }
        let app = payload["app"] as? [String: Any] ?? [:]
        let children = payload["children"] as? [String: Any] ?? [:]
        self.summary = Self.string(payload["summary"]) ?? ""
        self.appFootprintBytes = Self.int64(app["physical_footprint_bytes"])
        self.appResidentBytes = Self.int64(app["resident_bytes"])
        self.childRSSBytes = Self.int64(children["recursive_rss_bytes"])
        self.childProcessCount = Self.int(children["process_count"]) ?? 0
        self.groups = (children["groups"] as? [[String: Any]] ?? [])
            .compactMap(MosaicTaskManagerMemoryGroup.init)
    }

    static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int64(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String,
           let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return 0
    }

    static func int(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func intArray(_ raw: Any?) -> [Int] {
        if let values = raw as? [Int] { return values }
        guard let values = raw as? [Any] else { return [] }
        return values.compactMap(int)
    }
}

struct MosaicTaskManagerMemoryGroup: Sendable {
    let id: String
    let name: String
    let rssBytes: Int64
    let processCount: Int
    let processIds: [Int]
    let topAttribution: MosaicTaskManagerMemoryAttribution?

    init?(_ payload: [String: Any]) {
        guard let name = MosaicTaskManagerMemoryDiagnostic.string(payload["name"]) else {
            return nil
        }
        let processCount = MosaicTaskManagerMemoryDiagnostic.int(payload["process_count"]) ?? 0
        guard processCount > 0 else { return nil }
        self.id = MosaicTaskManagerMemoryDiagnostic.string(payload["id"]) ?? name.lowercased()
        self.name = name
        self.rssBytes = MosaicTaskManagerMemoryDiagnostic.int64(payload["rss_bytes"])
        self.processCount = processCount
        self.processIds = MosaicTaskManagerMemoryDiagnostic.intArray(payload["pids"])
        self.topAttribution = MosaicTaskManagerMemoryAttribution(payload["top_attribution"] as? [String: Any])
    }
}

struct MosaicTaskManagerMemoryAttribution: Sendable {
    let workspaceId: UUID?
    let workspaceRef: String?
    let paneId: UUID?
    let paneRef: String?
    let surfaceId: UUID?
    let surfaceRef: String?
    let surfaceType: String?

    init?(_ payload: [String: Any]?) {
        guard let payload else { return nil }
        self.workspaceId = Self.uuid(payload["workspace_id"])
        self.workspaceRef = MosaicTaskManagerMemoryDiagnostic.string(payload["workspace_ref"])
        self.paneId = Self.uuid(payload["pane_id"])
        self.paneRef = MosaicTaskManagerMemoryDiagnostic.string(payload["pane_ref"])
        self.surfaceId = Self.uuid(payload["surface_id"])
        self.surfaceRef = MosaicTaskManagerMemoryDiagnostic.string(payload["surface_ref"])
        self.surfaceType = MosaicTaskManagerMemoryDiagnostic.string(payload["surface_type"])
        if workspaceId == nil,
           workspaceRef == nil,
           paneId == nil,
           paneRef == nil,
           surfaceId == nil,
           surfaceRef == nil,
           surfaceType == nil {
            return nil
        }
    }

    private static func uuid(_ raw: Any?) -> UUID? {
        if let value = raw as? UUID {
            return value
        }
        guard let value = MosaicTaskManagerMemoryDiagnostic.string(raw) else {
            return nil
        }
        return UUID(uuidString: value)
    }
}

enum MosaicTaskManagerFormat {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    static func cpu(_ value: Double) -> String {
        String(format: "%.1f%%", max(0, value))
    }

    static func bytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(0, bytes))
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static func iso8601Date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoFormatter.date(from: raw)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

struct MosaicTaskManagerCodingAgentDefinition: Equatable {
    let id: String
    let displayName: String
    let assetName: String?
    let launchKinds: [String]
    let directBasenames: [String]
    let argumentNeedles: [String]

    static let builtIns: [MosaicTaskManagerCodingAgentDefinition] = [
        MosaicTaskManagerCodingAgentDefinition(
            id: "claude",
            displayName: "Claude Code",
            assetName: "AgentIcons/Claude",
            launchKinds: ["claude", "claudeteams", "claude-teams", "omc"],
            directBasenames: ["claude", "claude-code", "claude_code", "claude-teams", "omc"],
            argumentNeedles: [
                "claude-code",
                "claude_code",
                "claude-teams",
                "@anthropic-ai/claude-code",
                "oh-my-claude",
                "omc",
                "/.local/bin/claude",
                "/.local/share/claude/versions/",
                "/library/application support/claude/claude-code/",
            ]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "codex",
            displayName: "Codex",
            assetName: "AgentIcons/Codex",
            launchKinds: ["codex", "omx"],
            directBasenames: ["codex", "omx"],
            argumentNeedles: ["codex", "@openai/codex", "oh-my-codex"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "grok",
            displayName: "Grok",
            assetName: nil,
            launchKinds: ["grok"],
            directBasenames: ["grok", "grok-macos-aarch64", "grok-macos-aarch"],
            argumentNeedles: ["grok", "grok-build", "@xai/grok"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "opencode",
            displayName: "OpenCode",
            assetName: "AgentIcons/OpenCode",
            launchKinds: ["opencode", "omo"],
            directBasenames: ["opencode", "opencode-ai", "open-code", "omo"],
            argumentNeedles: ["opencode", "opencode-ai", "open-code", "oh-my-openagent"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "omp",
            displayName: "OMP",
            assetName: nil,
            launchKinds: ["omp"],
            directBasenames: ["omp"],
            argumentNeedles: ["@oh-my-pi/pi-coding-agent"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "pi",
            displayName: "Pi",
            assetName: "AgentIcons/Pi",
            launchKinds: ["pi"],
            directBasenames: ["pi", "pi-coding-agent"],
            argumentNeedles: ["@mariozechner/pi-coding-agent", "pi-coding-agent"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "amp",
            displayName: "Amp",
            assetName: nil,
            launchKinds: ["amp"],
            directBasenames: ["amp"],
            argumentNeedles: ["@ampcode"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "cursor",
            displayName: "Cursor",
            assetName: nil,
            launchKinds: ["cursor"],
            directBasenames: ["cursor-agent"],
            argumentNeedles: ["cursor-agent"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "gemini",
            displayName: "Gemini",
            assetName: nil,
            launchKinds: ["gemini"],
            directBasenames: ["gemini"],
            argumentNeedles: ["gemini"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "kiro",
            displayName: "Kiro",
            assetName: nil,
            launchKinds: ["kiro"],
            directBasenames: ["kiro", "kiro-cli"],
            argumentNeedles: ["kiro", "kiro-cli"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "antigravity",
            displayName: "Antigravity",
            assetName: "AgentIcons/Antigravity",
            launchKinds: ["antigravity", "agy"],
            directBasenames: ["agy", "antigravity"],
            argumentNeedles: ["antigravity-cli", "antigravity"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "rovodev",
            displayName: "Rovo Dev",
            assetName: "AgentIcons/RovoDev",
            launchKinds: ["rovodev", "rovo"],
            directBasenames: ["rovodev"],
            argumentNeedles: ["rovodev"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "hermes-agent",
            displayName: "Hermes Agent",
            assetName: "AgentIcons/HermesAgent",
            launchKinds: ["hermes-agent"],
            directBasenames: ["hermes", "hermes-agent"],
            argumentNeedles: ["hermes-agent"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "copilot",
            displayName: "Copilot",
            assetName: nil,
            launchKinds: ["copilot"],
            directBasenames: ["copilot"],
            argumentNeedles: ["copilot"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "codebuddy",
            displayName: "CodeBuddy",
            assetName: nil,
            launchKinds: ["codebuddy"],
            directBasenames: ["codebuddy"],
            argumentNeedles: ["codebuddy"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "factory",
            displayName: "Factory",
            assetName: nil,
            launchKinds: ["factory"],
            directBasenames: ["droid", "factory"],
            argumentNeedles: ["factory"]
        ),
        MosaicTaskManagerCodingAgentDefinition(
            id: "qoder",
            displayName: "Qoder",
            assetName: nil,
            launchKinds: ["qoder"],
            directBasenames: ["qoder", "qodercli"],
            argumentNeedles: ["qoder", "qodercli"]
        ),
    ]

    static func shouldReadArguments(processName: String, processPath: String?) -> Bool {
        if let normalizedPath = normalized(processPath),
           argumentInspectionPathNeedles.contains(where: { normalizedPath.contains($0) }) {
            return true
        }

        let basenames = candidateBasenames(
            processName: processName,
            processPath: processPath,
            arguments: []
        )
        return basenames.contains { candidate in
            argumentHostBasenames.contains(candidate)
                || ambiguousDirectBasenames.contains(candidate)
                || isVersionedExecutableBasename(candidate)
        }
    }

    static func matchingDefinition(
        processName: String,
        processPath: String?,
        arguments: [String],
        environment: [String: String]
    ) -> MosaicTaskManagerCodingAgentDefinition? {
        let definitions = builtIns
        let launchKind = normalized(environment["MOSAIC_AGENT_LAUNCH_KIND"])
        if let launchKind,
           let definition = definitions.first(where: { $0.launchKinds.contains(launchKind) }) {
            return definition
        }

        let basenames = candidateBasenames(
            processName: processName,
            processPath: processPath,
            arguments: arguments
        )
        if let definition = definitions.first(where: { definition in
            basenames.contains { definition.directBasenames.contains($0) }
        }) {
            return definition
        }

        guard !arguments.isEmpty else { return nil }
        return definitions.first { definition in
            definition.argumentNeedles.contains { needle in
                arguments.contains { argumentMatchesNeedle(argument: $0, needle: needle) }
            }
        }
    }

    /// Matches a coding-agent command without inspecting a live process.
    ///
    /// The parser accepts environment prefixes, command chains, and nested
    /// `sh -c`-style invocations so launch-time UI can use the same registry as
    /// process-based task-manager detection.
    static func matchingCommand(_ command: String) -> MosaicTaskManagerCodingAgentDefinition? {
        let tokens = shellLikeTokens(command)
        guard !tokens.isEmpty else { return nil }
        for segment in commandSegments(from: tokens) {
            if let definition = matchingCommandSegment(segment, depth: 0) {
                return definition
            }
        }
        return nil
    }

    private static func matchingCommandSegment(
        _ tokens: [String],
        depth: Int
    ) -> MosaicTaskManagerCodingAgentDefinition? {
        guard !tokens.isEmpty else { return nil }
        let resolved = resolvedCommandSegment(tokens)
        guard let executable = resolved.arguments.first else { return nil }
        let inspectedArguments = shouldReadArguments(
            processName: executable,
            processPath: executable
        ) ? resolved.arguments : []
        if let definition = matchingDefinition(
            processName: executable,
            processPath: executable,
            arguments: inspectedArguments,
            environment: resolved.environment
        ) {
            return definition
        }

        guard depth < 2 else { return nil }
        for segment in shellSubcommandSegments(from: resolved.arguments) {
            if let definition = matchingCommandSegment(segment, depth: depth + 1) {
                return definition
            }
        }
        return nil
    }

    private static func shellLikeTokens(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                flush()
                continue
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    private static func commandSegments(from tokens: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for token in tokens {
            if token == "&&" || token == "||" || token == ";" {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func resolvedCommandSegment(
        _ tokens: [String]
    ) -> (arguments: [String], environment: [String: String]) {
        var environment: [String: String] = [:]
        var index = 0
        let firstBasename = tokens.first.map { ($0 as NSString).lastPathComponent.lowercased() }

        if firstBasename == "env" {
            index = 1
            while index < tokens.count {
                let token = tokens[index]
                if token.hasPrefix("-") {
                    index += 1
                    continue
                }
                guard let assignment = environmentAssignment(token) else { break }
                environment[assignment.key] = assignment.value
                index += 1
            }
        } else {
            while index < tokens.count {
                guard let assignment = environmentAssignment(tokens[index]) else { break }
                environment[assignment.key] = assignment.value
                index += 1
            }
        }

        let arguments = Array(tokens.dropFirst(index))
        return (arguments.isEmpty ? tokens : arguments, environment)
    }

    private static func shellSubcommandSegments(from arguments: [String]) -> [[String]] {
        guard let executable = arguments.first else { return [] }
        let basename = (executable as NSString).lastPathComponent.lowercased()
        guard ["sh", "bash", "zsh", "fish"].contains(basename) else { return [] }

        var commandStartIndex: Int?
        for index in arguments.indices.dropFirst() {
            let argument = arguments[index]
            if argument == "-c" || argument == "-lc" || argument == "-cl" {
                commandStartIndex = arguments.index(after: index)
                break
            }
            if argument.hasPrefix("-"),
               !argument.hasPrefix("--"),
               argument.dropFirst().contains("c") {
                commandStartIndex = arguments.index(after: index)
                break
            }
        }

        guard let commandStartIndex,
              commandStartIndex < arguments.endIndex else {
            return []
        }
        let commandTokens = shellLikeTokens(arguments[commandStartIndex])
        guard !commandTokens.isEmpty else { return [] }
        return commandSegments(from: commandTokens)
    }

    private static func environmentAssignment(_ token: String) -> (key: String, value: String)? {
        guard let equalsIndex = token.firstIndex(of: "="),
              equalsIndex != token.startIndex else {
            return nil
        }
        let key = String(token[..<equalsIndex])
        guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return (key, String(token[token.index(after: equalsIndex)...]))
    }

    private static let argumentHostBasenames: Set<String> = [
        "node", "bun", "deno", "npm", "npx", "pnpm", "yarn", "tsx"
    ]

    private static let ambiguousDirectBasenames: Set<String> = [
        "acli"
    ]

    private static let argumentInspectionPathNeedles = [
        "/.local/share/claude/versions/",
        "/library/application support/claude/claude-code/",
    ]

    private static func candidateBasenames(
        processName: String,
        processPath: String?,
        arguments: [String]
    ) -> Set<String> {
        var values = Set<String>()
        appendBasename(processName, to: &values)
        if let processPath {
            appendBasename(processPath, to: &values)
        }
        if let executable = arguments.first {
            appendBasename(executable, to: &values)
        }
        return values
    }

    private static func appendBasename(_ value: String, to values: inout Set<String>) {
        guard let normalized = normalized((value as NSString).lastPathComponent) else { return }
        values.insert(normalized)
    }

    private static func isVersionedExecutableBasename(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }
    }

    private static func argumentMatchesNeedle(argument: String, needle: String) -> Bool {
        guard let normalizedArgument = normalized(argument),
              let normalizedNeedle = normalized(needle) else { return false }
        if normalizedNeedle.contains("/") {
            return containsNeedleWithBoundaries(normalizedNeedle, in: normalizedArgument)
        }
        return argumentTokens(from: normalizedArgument).contains(normalizedNeedle)
    }

    private static func containsNeedleWithBoundaries(_ needle: String, in value: String) -> Bool {
        var searchRange = value.startIndex..<value.endIndex
        while let range = value.range(of: needle, range: searchRange) {
            let previous = range.lowerBound == value.startIndex ? nil : value[value.index(before: range.lowerBound)]
            let next = range.upperBound == value.endIndex ? nil : value[range.upperBound]
            let hasLeadingBoundary = needle.hasPrefix("/") || isNeedleBoundary(previous)
            let hasTrailingBoundary = needle.hasSuffix("/") || isNeedleBoundary(next)
            if hasLeadingBoundary, hasTrailingBoundary {
                return true
            }
            searchRange = range.upperBound..<value.endIndex
        }
        return false
    }

    private static func isNeedleBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            argumentBoundaryScalars.contains(scalar)
        }
    }

    private static func argumentTokens(from value: String) -> Set<String> {
        let tokens = value
            .components(separatedBy: argumentTokenSeparators)
            .filter { !$0.isEmpty }
        return Set(tokens.flatMap { token in
            let stem = (token as NSString).deletingPathExtension
            return stem.isEmpty || stem == token ? [token] : [token, stem]
        })
    }

    private static let argumentTokenSeparators = CharacterSet(charactersIn: "/\\ \t\r\n\u{0}:=?&#\"'`<>(),;[]{}")

    private static let argumentBoundaryScalars = CharacterSet(charactersIn: "/\\ \t\r\n\u{0}:=?&#\"'`<>(),;[]{}").union(.newlines)

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
