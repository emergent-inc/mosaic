import Foundation
import MosaicFoundation

extension MosaicCLI {
    func runConfigCommand(
        commandArgs: [String],
        socketPath: String?,
        explicitPassword: String?,
        jsonOutput: Bool
    ) throws {
        let parsedArgs = docsSettingsArguments(commandArgs)
        let wantsJSON = jsonOutput || parsedArgs.head.contains("--json")
        let args = parsedArgs.arguments
        let subcommand = args.first?.lowercased() ?? "help"

        if hasHelpRequest(beforeSeparator: parsedArgs.head) {
            print(configUsage())
            return
        }

        switch subcommand {
        case "help":
            print(configUsage())
        case "get":
            guard args.count == 2, let key = canonicalFontSizeKey(args[1]) else {
                throw CLIError(message: "Usage: mosaic config get <sidebar-font-size|surface-tab-bar-font-size>")
            }
            try runConfigGetFontSize(forKey: key, jsonOutput: wantsJSON)
        case "set":
            guard args.count == 3, let key = canonicalFontSizeKey(args[1]) else {
                throw CLIError(message: "Usage: mosaic config set <sidebar-font-size|surface-tab-bar-font-size> <points>")
            }
            try runConfigSetFontSize(
                forKey: key,
                rawValue: args[2],
                socketPath: socketPath,
                explicitPassword: explicitPassword,
                jsonOutput: wantsJSON
            )
        case MosaicGhosttyConfigSettingEditor.sidebarFontSizeKey, MosaicGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey:
            if args.count == 1 {
                try runConfigGetFontSize(forKey: subcommand, jsonOutput: wantsJSON)
            } else if args.count == 2 {
                try runConfigSetFontSize(
                    forKey: subcommand,
                    rawValue: args[1],
                    socketPath: socketPath,
                    explicitPassword: explicitPassword,
                    jsonOutput: wantsJSON
                )
            } else {
                throw CLIError(message: "Usage: mosaic config \(subcommand) [points]")
            }
        case "path", "paths":
            guard args.count == 1 else {
                throw CLIError(message: "Usage: mosaic config path")
            }
            printSettingsPaths(jsonOutput: wantsJSON)
        case "docs", "documentation":
            guard args.count == 1 else {
                throw CLIError(message: "Usage: mosaic config docs")
            }
            try runDocsCommand(commandArgs: ["settings"], jsonOutput: wantsJSON)
        case "doctor", "check", "validate":
            let doctorArgs = Array(args.dropFirst())
            let report = try runConfigDoctor(arguments: doctorArgs, jsonOutput: wantsJSON)
            if report.errorCount > 0 {
                throw CLIError(message: "mosaic config doctor found \(report.errorCount) error(s)")
            }
        case "reload":
            guard args.count == 1 else {
                throw CLIError(message: "Usage: mosaic config reload")
            }
            guard let socketPath else {
                throw CLIError(message: "mosaic config reload requires a socket-backed mosaic command path")
            }
            let client = try connectClient(
                socketPath: socketPath,
                explicitPassword: explicitPassword,
                launchIfNeeded: false
            )
            defer { client.close() }
            let response = try client.send(command: "reload_config")
            if response.hasPrefix("ERROR:") {
                throw CLIError(message: response)
            }
            print(response)
        default:
            throw CLIError(message: "Unknown config subcommand '\(subcommand)'. Run 'mosaic config --help'.")
        }
    }

    func configCommandDoesNotNeedSocket(_ commandArgs: [String]) -> Bool {
        let parsedArgs = docsSettingsArguments(commandArgs)
        let subcommand = parsedArgs.arguments.first?.lowercased() ?? "help"
        if subcommand == "get" {
            return true
        }
        if subcommand == MosaicGhosttyConfigSettingEditor.sidebarFontSizeKey
            || subcommand == MosaicGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey {
            return parsedArgs.arguments.count == 1
        }
        return hasHelpRequest(beforeSeparator: parsedArgs.head) ||
            ["help", "path", "paths", "docs", "documentation", "doctor", "check", "validate"].contains(subcommand)
    }

    func configUsage() -> String {
        return """
        Usage: mosaic config <doctor|check|validate|path|paths|docs|documentation|reload|get|set|sidebar-font-size|surface-tab-bar-font-size>

        Inspect mosaic.json, print configuration references, update selected Ghostty config keys, or reload the running app.

        Subcommands:
          doctor|check|validate [--path <path>]   Validate JSONC syntax for mosaic config files.
          path|paths                              Print mosaic.json paths, docs URL, and schema URL.
          docs|documentation                      Print the same output as `mosaic docs settings`.
          reload                                  Reload Ghostty config + mosaic.json and refresh terminals (alias for `mosaic reload-config`).
          get <key>                               Print sidebar-font-size or surface-tab-bar-font-size.
          set <key> <points>                      Set sidebar-font-size (10-20 pt) or surface-tab-bar-font-size (8-24 pt), then reload if mosaic is running.
          sidebar-font-size [points]              Get or set the left sidebar text size.
          surface-tab-bar-font-size [points]      Get or set the workspace tab bar text size.

        Config files:
          \(Self.primarySettingsDisplayPath)
          legacy config: \(Self.legacySettingsDisplayPath)
          legacy app support: \(Self.fallbackSettingsDisplayPath)

        Related (not mosaic-owned, but mosaic reads it for terminal behavior):
          \(Self.ghosttyConfigDisplayPath)

        Examples:
          mosaic config doctor
          mosaic config doctor --path .mosaic/mosaic.json
          mosaic config set sidebar-font-size 14
          mosaic config sidebar-font-size 12.5
          mosaic config set surface-tab-bar-font-size 13
          mosaic config surface-tab-bar-font-size 11
          mosaic config reload
        """
    }

    func printSettingsPaths(jsonOutput: Bool) {
        let payload: [String: Any] = [
            "primary": Self.primarySettingsDisplayPath,
            "legacy": Self.legacySettingsDisplayPath,
            "fallback": Self.fallbackSettingsDisplayPath,
            "ghostty_config": [
                "path": Self.ghosttyConfigDisplayPath,
                "note": "Not mosaic-owned, but mosaic reads it. Use for terminal transparency (background-opacity), blur, font, theme, etc.",
            ],
            "docs_url": Self.settingsDocsURL,
            "schema_url": Self.settingsSchemaURL,
            "reload_command": "mosaic reload-config",
            "reload_scope": "Reloads Ghostty config + mosaic.json and refreshes terminals in place. No app restart needed.",
            "backup": "Back up any existing mosaic.json file to a timestamped .bak copy before editing so the user can revert.",
        ]

        if jsonOutput {
            print(jsonString(payload))
            return
        }

        print("Config files:")
        print("  primary:  \(Self.primarySettingsDisplayPath)")
        print("  legacy config: \(Self.legacySettingsDisplayPath)")
        print("  legacy app support: \(Self.fallbackSettingsDisplayPath)")
        print()
        print("Related (not mosaic-owned, but mosaic reads it for terminal behavior):")
        print("  \(Self.ghosttyConfigDisplayPath)")
        print()
        print("Docs:")
        print("  \(Self.settingsDocsURL)")
        print()
        print("Schema:")
        print("  \(Self.settingsSchemaURL)")
        print()
        print("Before editing mosaic.json:")
        print("  Back up any existing mosaic.json file to a timestamped .bak copy so the user can revert.")
        print()
        print("Reload after editing (covers BOTH mosaic.json and Ghostty config; no app restart needed):")
        print("  mosaic reload-config")
    }

    /// Normalizes a user-supplied key to a supported editable font-size key, or nil if unsupported.
    private func canonicalFontSizeKey(_ raw: String) -> String? {
        switch raw.lowercased() {
        case MosaicGhosttyConfigSettingEditor.sidebarFontSizeKey:
            return MosaicGhosttyConfigSettingEditor.sidebarFontSizeKey
        case MosaicGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey:
            return MosaicGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey
        default:
            return nil
        }
    }

    private func fontSizeConfig(
        forKey key: String
    ) -> (defaultValue: Double, clamp: (Double) -> Double, format: (Double) -> String, parse: (String) -> Double?)? {
        switch key {
        case MosaicGhosttyConfigSettingEditor.sidebarFontSizeKey:
            return (
                MosaicGhosttyConfigSettingEditor.defaultSidebarFontSize,
                MosaicGhosttyConfigSettingEditor().clampedSidebarFontSize,
                MosaicGhosttyConfigSettingEditor().formattedSidebarFontSize,
                { MosaicGhosttyConfigSettingEditor().parsedSidebarFontSize(in: $0) }
            )
        case MosaicGhosttyConfigSettingEditor.surfaceTabBarFontSizeKey:
            return (
                MosaicGhosttyConfigSettingEditor.defaultSurfaceTabBarFontSize,
                MosaicGhosttyConfigSettingEditor().clampedSurfaceTabBarFontSize,
                MosaicGhosttyConfigSettingEditor().formattedSurfaceTabBarFontSize,
                { MosaicGhosttyConfigSettingEditor().parsedSurfaceTabBarFontSize(in: $0) }
            )
        default:
            return nil
        }
    }

    private func runConfigGetFontSize(forKey key: String, jsonOutput: Bool) throws {
        guard let descriptor = fontSizeConfig(forKey: key) else {
            throw CLIError(message: "Unknown font size key '\(key)'")
        }
        let url = try mosaicGhosttyConfigURLForCLI()
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let configuredValue = descriptor.parse(contents)
        let effectiveValue = configuredValue ?? descriptor.defaultValue
        let formattedValue = descriptor.format(effectiveValue)

        if jsonOutput {
            var payload: [String: Any] = [
                "key": key,
                "value": effectiveValue,
                "formatted": formattedValue,
                "path": url.path,
                "configured": configuredValue != nil,
            ]
            if let configuredValue {
                payload["configured_value"] = configuredValue
            }
            print(jsonString(payload))
            return
        }

        print("\(key) = \(formattedValue)")
        print("path: \(Self.tildePath(url.path))")
    }

    private func runConfigSetFontSize(
        forKey key: String,
        rawValue: String,
        socketPath: String?,
        explicitPassword: String?,
        jsonOutput: Bool
    ) throws {
        guard let descriptor = fontSizeConfig(forKey: key) else {
            throw CLIError(message: "Unknown font size key '\(key)'")
        }
        guard let requestedValue = Double(rawValue), requestedValue.isFinite else {
            throw CLIError(message: "\(key) requires a numeric point size")
        }

        let value = descriptor.clamp(requestedValue)
        let formattedValue = descriptor.format(value)
        let url = try mosaicGhosttyConfigURLForCLI()
        try MosaicGhosttyConfigSettingEditor().writeSetting(
            key: key,
            value: formattedValue,
            to: url
        )

        let reloadResult = reloadConfigAfterFontSizeSet(
            socketPath: socketPath,
            explicitPassword: explicitPassword
        )

        if jsonOutput {
            var payload: [String: Any] = [
                "ok": true,
                "key": key,
                "value": value,
                "formatted": formattedValue,
                "path": url.path,
                "reload": reloadResult.status,
                "clamped": value != requestedValue,
            ]
            if let message = reloadResult.message {
                payload["reload_message"] = message
            }
            print(jsonString(payload))
            return
        }

        switch reloadResult.status {
        case "reloaded":
            print("OK \(key) = \(formattedValue) (reloaded)")
        case "failed":
            print("OK \(key) = \(formattedValue) (saved; reload failed)")
            if let message = reloadResult.message {
                print("reload: \(message)")
            }
            print("Run `mosaic config reload` after mosaic is running to apply it.")
        default:
            print("OK \(key) = \(formattedValue) (saved)")
            print("Run `mosaic config reload` to apply it.")
        }
        print("path: \(Self.tildePath(url.path))")
    }

    private func mosaicGhosttyConfigURLForCLI() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default
        let appSupportDirectories = MosaicApplicationSupportDirectories(environment: environment, fileManager: fileManager)
            .userDirectories
        guard let firstAppSupportDirectory = appSupportDirectories.first else {
            throw CLIError(message: "Could not resolve the user Application Support directory")
        }
        let bundleIdentifier = normalizedConfigValue(environment["MOSAIC_BUNDLE_ID"])
            ?? CLISocketPathResolver.currentAppBundleIdentifier()
        // Prefer an existing config under any candidate root (the app loads config
        // across all Application Support locations, including CFFIXED_USER_HOME),
        // so `config get/set` touches the same file the app reads. Fall back to
        // creating one under the first candidate when none exists yet.
        for appSupportDirectory in appSupportDirectories {
            if let existing = MosaicGhosttyConfigPathResolver().loadConfigURLs(
                currentBundleIdentifier: bundleIdentifier,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ).first {
                return existing
            }
        }
        return MosaicGhosttyConfigPathResolver().activeOrEditableConfigURL(
            currentBundleIdentifier: bundleIdentifier,
            appSupportDirectory: firstAppSupportDirectory,
            fileManager: fileManager
        )
    }

    private func reloadConfigAfterFontSizeSet(
        socketPath: String?,
        explicitPassword: String?
    ) -> (status: String, message: String?) {
        guard let socketPath else {
            return ("skipped", nil)
        }
        do {
            let client = try connectClient(
                socketPath: socketPath,
                explicitPassword: explicitPassword,
                launchIfNeeded: false
            )
            defer { client.close() }
            let response = try client.send(command: "reload_config")
            if response.hasPrefix("ERROR:") {
                return ("failed", response)
            }
            return ("reloaded", response)
        } catch {
            return ("failed", Self.configDoctorErrorMessage(error))
        }
    }

    private func normalizedConfigValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct ConfigDoctorOptions {
        let paths: [String]
    }

    private struct ConfigDoctorTarget {
        let label: String
        let displayPath: String
        let path: String
        let missingIsError: Bool
    }

    private struct ConfigDoctorFinding {
        let label: String
        let displayPath: String
        let path: String
        let status: String
        let message: String?
        let keys: [String]
        let byteCount: Int?

        var isError: Bool { status == "error" }

        var payload: [String: Any] {
            var result: [String: Any] = [
                "label": label,
                "display_path": displayPath,
                "path": path,
                "status": status,
                "ok": !isError,
                "keys": keys,
            ]
            if let message {
                result["message"] = message
            }
            if let byteCount {
                result["bytes"] = byteCount
            }
            return result
        }
    }

    private struct ConfigDoctorReport {
        let findings: [ConfigDoctorFinding]

        var errorCount: Int {
            findings.filter(\.isError).count
        }

        var payload: [String: Any] {
            [
                "ok": errorCount == 0,
                "error_count": errorCount,
                "findings": findings.map(\.payload),
                "reload_command": "mosaic reload-config",
                "docs_url": MosaicCLI.settingsDocsURL,
                "schema_url": MosaicCLI.settingsSchemaURL,
            ]
        }
    }

    private func runConfigDoctor(arguments: [String], jsonOutput: Bool) throws -> ConfigDoctorReport {
        let options = try parseConfigDoctorOptions(arguments)
        let targets = options.paths.isEmpty
            ? defaultConfigDoctorTargets()
            : options.paths.enumerated().map { index, rawPath in
                let path = Self.absoluteConfigPath(rawPath)
                return ConfigDoctorTarget(
                    label: "custom \(index + 1)",
                    displayPath: Self.tildePath(path),
                    path: path,
                    missingIsError: true
                )
            }
        let findings = targets.map(configDoctorFinding(for:))
        let report = ConfigDoctorReport(findings: findings)

        if jsonOutput {
            print(jsonString(report.payload))
        } else {
            printConfigDoctorReport(report)
        }
        return report
    }

    private func parseConfigDoctorOptions(_ arguments: [String]) throws -> ConfigDoctorOptions {
        var paths: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--path" {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError(message: "mosaic config doctor --path requires a path")
                }
                paths.append(arguments[nextIndex])
                index += 2
                continue
            }
            if argument.hasPrefix("--path=") {
                let rawPath = String(argument.dropFirst("--path=".count))
                guard !rawPath.isEmpty else {
                    throw CLIError(message: "mosaic config doctor --path requires a path")
                }
                paths.append(rawPath)
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                throw CLIError(message: "Unknown config doctor option '\(argument)'")
            }
            throw CLIError(message: "Unknown config doctor argument '\(argument)'. Use --path <path>.")
        }
        return ConfigDoctorOptions(paths: paths)
    }

    private func defaultConfigDoctorTargets() -> [ConfigDoctorTarget] {
        let primary = Self.absoluteConfigPath(Self.primarySettingsDisplayPath)
        var targets = [
            ConfigDoctorTarget(
                label: "primary",
                displayPath: Self.primarySettingsDisplayPath,
                path: primary,
                missingIsError: false
            )
        ]

        if let projectPath = findProjectConfigPath(), projectPath != primary {
            targets.append(
                ConfigDoctorTarget(
                    label: "project",
                    displayPath: Self.tildePath(projectPath),
                    path: projectPath,
                    missingIsError: false
                )
            )
        }

        let optionalPaths = [
            ("legacy config", Self.legacySettingsDisplayPath),
            ("legacy app support", Self.fallbackSettingsDisplayPath),
        ]
        for (label, displayPath) in optionalPaths {
            let path = Self.absoluteConfigPath(displayPath)
            guard path != primary,
                  FileManager.default.fileExists(atPath: path),
                  !targets.contains(where: { $0.path == path }) else {
                continue
            }
            targets.append(
                ConfigDoctorTarget(
                    label: label,
                    displayPath: displayPath,
                    path: path,
                    missingIsError: false
                )
            )
        }
        return targets
    }

    private func findProjectConfigPath() -> String? {
        let fileManager = FileManager.default
        let rawHomePath = ProcessInfo.processInfo.environment["HOME"] ?? fileManager.homeDirectoryForCurrentUser.path
        let homePath = URL(fileURLWithPath: rawHomePath).standardizedFileURL.path
        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL.path
        while true {
            if current == homePath {
                return nil
            }
            let candidates = [
                ((current as NSString).appendingPathComponent(".mosaic") as NSString)
                    .appendingPathComponent("mosaic.json"),
                (current as NSString).appendingPathComponent("mosaic.json"),
            ]
            for candidate in candidates {
                var isDirectory = ObjCBool(false)
                if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    return URL(fileURLWithPath: candidate).standardizedFileURL.path
                }
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    private func configDoctorFinding(for target: ConfigDoctorTarget) -> ConfigDoctorFinding {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            let message = target.missingIsError
                ? "file not found"
                : "not found; mosaic will use defaults until this file exists"
            return ConfigDoctorFinding(
                label: target.label,
                displayPath: target.displayPath,
                path: target.path,
                status: target.missingIsError ? "error" : "missing",
                message: message,
                keys: [],
                byteCount: nil
            )
        }
        if isDirectory.boolValue {
            return ConfigDoctorFinding(
                label: target.label,
                displayPath: target.displayPath,
                path: target.path,
                status: "error",
                message: "path is a directory, expected a file",
                keys: [],
                byteCount: nil
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: target.path))
            guard !data.isEmpty else {
                return ConfigDoctorFinding(
                    label: target.label,
                    displayPath: target.displayPath,
                    path: target.path,
                    status: "error",
                    message: "file is empty",
                    keys: [],
                    byteCount: 0
                )
            }
            let sanitized = try JSONCParser.preprocess(data: data)
            let object = try JSONSerialization.jsonObject(with: sanitized)
            guard let dictionary = object as? [String: Any] else {
                return ConfigDoctorFinding(
                    label: target.label,
                    displayPath: target.displayPath,
                    path: target.path,
                    status: "error",
                    message: "top-level value must be a JSON object",
                    keys: [],
                    byteCount: data.count
                )
            }
            return ConfigDoctorFinding(
                label: target.label,
                displayPath: target.displayPath,
                path: target.path,
                status: "ok",
                message: "JSONC syntax is valid",
                keys: dictionary.keys.sorted(),
                byteCount: data.count
            )
        } catch {
            return ConfigDoctorFinding(
                label: target.label,
                displayPath: target.displayPath,
                path: target.path,
                status: "error",
                message: Self.configDoctorErrorMessage(error),
                keys: [],
                byteCount: nil
            )
        }
    }

    private func printConfigDoctorReport(_ report: ConfigDoctorReport) {
        print("mosaic config doctor")
        for finding in report.findings {
            print("\(finding.status.uppercased()) \(finding.label): \(finding.displayPath)")
            print("  path: \(finding.path)")
            if let byteCount = finding.byteCount {
                print("  bytes: \(byteCount)")
            }
            if !finding.keys.isEmpty {
                print("  keys: \(finding.keys.joined(separator: ", "))")
            }
            if let message = finding.message {
                print("  \(message)")
            }
        }
        print()
        print("Docs: \(Self.settingsDocsURL)")
        print("Schema: \(Self.settingsSchemaURL)")
        print("Reload: mosaic reload-config")
    }

    private static func absoluteConfigPath(_ rawPath: String) -> String {
        let homePath = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let expanded: String
        if rawPath == "~" {
            expanded = homePath
        } else if rawPath.hasPrefix("~/") {
            expanded = (homePath as NSString).appendingPathComponent(String(rawPath.dropFirst(2)))
        } else {
            expanded = rawPath
        }

        let absolute = (expanded as NSString).isAbsolutePath
            ? expanded
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
        return URL(fileURLWithPath: absolute).standardizedFileURL.path
    }

    private static func tildePath(_ path: String) -> String {
        let homePath = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
            .standardizedFileURL
            .path
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalized == homePath {
            return "~"
        }
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        if normalized.hasPrefix(prefix) {
            return "~/" + String(normalized.dropFirst(prefix.count))
        }
        return normalized
    }

    private static func configDoctorErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
            let trimmed = debug.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let described = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if !described.isEmpty {
            return described
        }
        let localized = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty {
            return localized
        }
        return "unknown config parse error"
    }
}
