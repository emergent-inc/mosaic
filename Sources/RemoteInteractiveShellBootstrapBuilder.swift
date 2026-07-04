import Foundation

enum RemoteInteractiveShellBootstrapBuilder {
    static func script(
        remoteRelayPort: Int,
        shellFeatures: String,
        terminfoSource: String? = nil,
        bundledZshIntegration: String? = nil,
        bundledBashIntegration: String? = nil,
        bundledFishIntegration: String? = nil
    ) -> String {
        let shellStateDir = shellStateDirForRemoteRelayPort(remoteRelayPort)
        let commonShellExportLines = commonShellLines(
            remoteRelayPort: remoteRelayPort,
            shellStateDir: shellStateDir,
            shellFeatures: shellFeatures,
            terminfoSource: terminfoSource
        )
        var zshShellLines = commonShellExportLines
        zshShellLines.append(
            #"if [ "${MOSAIC_SHELL_INTEGRATION:-1}" != "0" ] && [ -r "${MOSAIC_SHELL_INTEGRATION_DIR}/mosaic-zsh-integration.zsh" ]; then . "${MOSAIC_SHELL_INTEGRATION_DIR}/mosaic-zsh-integration.zsh"; fi"#
        )
        var bashShellLines = commonShellExportLines
        bashShellLines.append(
            #"if [ "${MOSAIC_SHELL_INTEGRATION:-1}" != "0" ] && [ -r "${MOSAIC_SHELL_INTEGRATION_DIR}/mosaic-bash-integration.bash" ]; then . "${MOSAIC_SHELL_INTEGRATION_DIR}/mosaic-bash-integration.bash"; fi"#
        )
        let zshBootstrap = RemoteRelayZshBootstrap(shellStateDir: shellStateDir)
        let relayWarmupLines = relayWarmupLines(remoteRelayPort: remoteRelayPort)

        var outerLines: [String] = [
            "mkdir -p \"$HOME/.mosaic/relay\"",
            "mosaic_shell_dir=\"\(shellStateDir)\"",
            "mkdir -p \"$mosaic_shell_dir\"",
        ]
        if let bundledZshIntegration {
            outerLines += [
                "cat > \"$mosaic_shell_dir/mosaic-zsh-integration.zsh\" <<'MOSAICMOSAICZSH'",
                bundledZshIntegration,
                "MOSAICMOSAICZSH",
            ]
        }
        if let bundledBashIntegration {
            outerLines += [
                "cat > \"$mosaic_shell_dir/mosaic-bash-integration.bash\" <<'MOSAICMOSAICBASH'",
                bundledBashIntegration,
                "MOSAICMOSAICBASH",
            ]
        }
        if let bundledFishIntegration {
            outerLines += [
                "mkdir -p \"$mosaic_shell_dir/fish\"",
                "cat > \"$mosaic_shell_dir/fish/config.fish\" <<'MOSAICMOSAICFISH'",
                bundledFishIntegration,
                "MOSAICMOSAICFISH",
            ]
        }
        outerLines.append(contentsOf: commonShellExportLines)
        outerLines += [
            "MOSAIC_LOGIN_SHELL=\"${SHELL:-/bin/zsh}\"",
            "case \"${MOSAIC_LOGIN_SHELL##*/}\" in",
            "  zsh)",
            "    cat > \"$mosaic_shell_dir/.zshenv\" <<'MOSAICZSHENV'",
        ]
        outerLines.append(contentsOf: zshBootstrap.zshEnvLines)
        outerLines += [
            "MOSAICZSHENV",
            "    cat > \"$mosaic_shell_dir/.zprofile\" <<'MOSAICZSHPROFILE'",
        ]
        outerLines.append(contentsOf: zshBootstrap.zshProfileLines)
        outerLines += [
            "MOSAICZSHPROFILE",
            "    cat > \"$mosaic_shell_dir/.zshrc\" <<'MOSAICZSHRC'",
        ]
        outerLines.append(contentsOf: zshBootstrap.zshRCLines(commonShellLines: zshShellLines))
        outerLines += [
            "MOSAICZSHRC",
            "    cat > \"$mosaic_shell_dir/.zlogin\" <<'MOSAICZSHLOGIN'",
        ]
        outerLines.append(contentsOf: zshBootstrap.zshLoginLines)
        outerLines += [
            "MOSAICZSHLOGIN",
            "    chmod 600 \"$mosaic_shell_dir/.zshenv\" \"$mosaic_shell_dir/.zprofile\" \"$mosaic_shell_dir/.zshrc\" \"$mosaic_shell_dir/.zlogin\" >/dev/null 2>&1 || true",
        ]
        outerLines.append(contentsOf: relayWarmupLines.map { "    " + $0 })
        outerLines += [
            "    export MOSAIC_REAL_ZDOTDIR=\"${ZDOTDIR:-$HOME}\"",
            "    export ZDOTDIR=\"$mosaic_shell_dir\"",
            "    exec \"$MOSAIC_LOGIN_SHELL\" -il",
            "    ;;",
            "  bash)",
            "    cat > \"$mosaic_shell_dir/.bashrc\" <<'MOSAICBASHRC'",
        ]
        outerLines.append(contentsOf: [
            "if [ -f \"$HOME/.bash_profile\" ]; then",
            "  . \"$HOME/.bash_profile\"",
            "elif [ -f \"$HOME/.bash_login\" ]; then",
            "  . \"$HOME/.bash_login\"",
            "elif [ -f \"$HOME/.profile\" ]; then",
            "  . \"$HOME/.profile\"",
            "fi",
            "[ -f \"$HOME/.bashrc\" ] && . \"$HOME/.bashrc\"",
        ] + bashShellLines)
        outerLines += [
            "MOSAICBASHRC",
            "    chmod 600 \"$mosaic_shell_dir/.bashrc\" >/dev/null 2>&1 || true",
        ]
        outerLines.append(contentsOf: relayWarmupLines.map { "    " + $0 })
        outerLines += [
            "    exec \"$MOSAIC_LOGIN_SHELL\" --rcfile \"$mosaic_shell_dir/.bashrc\" -i",
            "    ;;",
            "  fish)",
        ]
        outerLines.append(contentsOf: relayWarmupLines.map { "    " + $0 })
        outerLines += [
            "    export MOSAIC_FISH_INTEGRATION_FILE=\"$mosaic_shell_dir/fish/config.fish\"",
            "    export MOSAIC_FISH_USER_CONFIG_ALREADY_LOADED=1",
            "    exec \"$MOSAIC_LOGIN_SHELL\" -il --init-command 'source \"$MOSAIC_FISH_INTEGRATION_FILE\"'",
            "    ;;",
            "  *)",
        ]
        outerLines.append(contentsOf: relayWarmupLines)
        outerLines += [
            "exec \"$MOSAIC_LOGIN_SHELL\" -i",
            ";;",
            "esac",
        ]

        return outerLines.joined(separator: "\n")
    }

    static func shellFeatures(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let rawExisting = environment["GHOSTTY_SHELL_FEATURES"] ?? ""
        var seen: Set<String> = []
        var merged: [String] = []

        for token in rawExisting.split(separator: ",") {
            let feature = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !feature.isEmpty else { continue }
            if seen.insert(feature).inserted {
                merged.append(feature)
            }
        }

        for required in ["ssh-env", "ssh-terminfo"] {
            if seen.insert(required).inserted {
                merged.append(required)
            }
        }

        return merged.joined(separator: ",")
    }

    static func bundledShellIntegrationScript(
        named fileName: String,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let bundleResourceURL else { return nil }
        let url = bundleResourceURL
            .appendingPathComponent("shell-integration", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }
        return contents
    }

    private static func commonShellLines(
        remoteRelayPort: Int,
        shellStateDir: String,
        shellFeatures: String,
        terminfoSource: String?
    ) -> [String] {
        let relaySocket = remoteRelayPort > 0 ? "127.0.0.1:\(remoteRelayPort)" : nil
        var lines = terminalSetupLines(terminfoSource: terminfoSource)
        lines.append(contentsOf: RemoteShellEnvironment.utf8LocaleSetupLines())
        lines.append(contentsOf: shellExportLines(shellFeatures: shellFeatures))
        lines.append("export PATH=\"$HOME/.mosaic/bin:$PATH\"")
        lines.append("export MOSAIC_BUNDLED_CLI_PATH=\"$HOME/.mosaic/bin/mosaic\"")
        lines.append("export MOSAIC_SHELL_INTEGRATION_DIR=\"\(shellStateDir)\"")
        if let relaySocket {
            lines.append("export MOSAIC_SOCKET_PATH=\(relaySocket)")
        }
        // The assignment placeholders are replaced by `ssh-pty-attach` before
        // this script runs. Split the sentinel patterns so a missed replacement
        // does not export literal placeholder IDs into the remote shell.
        lines.append(contentsOf: [
            "mosaic_workspace_id='__MOSAIC_WORKSPACE_ID__'",
            "case \"$mosaic_workspace_id\" in \"\"|'__MOSAIC_''WORKSPACE_ID__') ;; *) export MOSAIC_WORKSPACE_ID=\"$mosaic_workspace_id\"; export MOSAIC_TAB_ID=\"$mosaic_workspace_id\" ;; esac",
            "mosaic_surface_id='__MOSAIC_SURFACE_ID__'",
            "case \"$mosaic_surface_id\" in \"\"|'__MOSAIC_''SURFACE_ID__') ;; *) export MOSAIC_SURFACE_ID=\"$mosaic_surface_id\"; export MOSAIC_PANEL_ID=\"$mosaic_surface_id\" ;; esac",
            "unset mosaic_workspace_id mosaic_surface_id",
            "hash -r >/dev/null 2>&1 || true",
            "rehash >/dev/null 2>&1 || true",
        ])
        return lines
    }

    static func terminalSetupLines(terminfoSource: String?) -> [String] {
        let trimmedTerminfoSource = terminfoSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTerminfoSource, !trimmedTerminfoSource.isEmpty else {
            // Without a bundled terminfo to install we can only probe what the
            // remote already has and fall back to a universally-present entry.
            return [
                "mosaic_term='xterm-256color'",
                "if command -v infocmp >/dev/null 2>&1 && infocmp xterm-ghostty >/dev/null 2>&1; then",
                "  mosaic_term='xterm-ghostty'",
                "fi",
                "export TERM=\"$mosaic_term\"",
            ]
        }
        // Install the bundled xterm-ghostty terminfo *synchronously*, before
        // deciding TERM, so a full-screen TUI (e.g. Claude Code) never starts
        // against a TERM whose terminfo entry is missing or half-written.
        //
        // The previous design deferred `tic` to a background job and decided
        // TERM up front, so the first shell on a host without the entry got
        // xterm-256color while a later pass could select xterm-ghostty mid-write
        // and garble output (#6352). Here we compile into a private temp
        // directory on the same filesystem as ~/.terminfo, then move each
        // compiled entry into place with an atomic rename, so a concurrent reader
        // in another mosaic ssh session sharing $HOME never observes a partially
        // written database. The temp directory comes from `mktemp` when present,
        // otherwise a per-process `$$` directory (unique among live processes) so
        // the atomic-rename path applies even without `mktemp` — no branch ever
        // compiles terminfo directly into ~/.terminfo.
        return [
            "mosaic_term='xterm-256color'",
            "if command -v infocmp >/dev/null 2>&1 && infocmp xterm-ghostty >/dev/null 2>&1; then",
            "  mosaic_term='xterm-ghostty'",
            "elif command -v tic >/dev/null 2>&1; then",
            "  mkdir -p \"$HOME/.terminfo\" 2>/dev/null",
            "  mosaic_ti_tmp=$(mktemp -d \"$HOME/.terminfo.mosaic.XXXXXX\" 2>/dev/null) || mosaic_ti_tmp=''",
            "  if [ -z \"$mosaic_ti_tmp\" ]; then",
            "    mosaic_ti_tmp=\"$HOME/.terminfo.mosaic.$$\"",
            "    rm -rf \"$mosaic_ti_tmp\" 2>/dev/null",
            "    mkdir \"$mosaic_ti_tmp\" 2>/dev/null || mosaic_ti_tmp=''",
            "  fi",
            "  {",
            "    cat <<'MOSAICTERMINFO'",
            trimmedTerminfoSource,
            "MOSAICTERMINFO",
            "  } | {",
            "    if [ -n \"$mosaic_ti_tmp\" ] && tic -x -o \"$mosaic_ti_tmp\" - >/dev/null 2>&1; then",
            "      find \"$mosaic_ti_tmp\" -type f 2>/dev/null | while IFS= read -r mosaic_ti_file; do",
            "        mosaic_ti_rel=${mosaic_ti_file#\"$mosaic_ti_tmp\"/}",
            "        mosaic_ti_dest=\"$HOME/.terminfo/$mosaic_ti_rel\"",
            "        mkdir -p \"$(dirname \"$mosaic_ti_dest\")\" 2>/dev/null",
            "        mv -f \"$mosaic_ti_file\" \"$mosaic_ti_dest\" 2>/dev/null || cp -f \"$mosaic_ti_file\" \"$mosaic_ti_dest\" 2>/dev/null",
            "      done",
            "    fi",
            "  }",
            "  [ -n \"$mosaic_ti_tmp\" ] && rm -rf \"$mosaic_ti_tmp\" 2>/dev/null",
            "  if infocmp xterm-ghostty >/dev/null 2>&1; then",
            "    mosaic_term='xterm-ghostty'",
            "  fi",
            "  unset mosaic_ti_tmp mosaic_ti_file mosaic_ti_rel mosaic_ti_dest 2>/dev/null || true",
            "fi",
            "export TERM=\"$mosaic_term\"",
        ]
    }

    private static func shellExportLines(shellFeatures: String) -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let colorTerm = normalizedEnvValue(environment["COLORTERM"]) ?? "truecolor"
        let termProgram = normalizedEnvValue(environment["TERM_PROGRAM"]) ?? "ghostty"
        let termProgramVersion = normalizedEnvValue(environment["TERM_PROGRAM_VERSION"])
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? ""
        let trimmedShellFeatures = shellFeatures.trimmingCharacters(in: .whitespacesAndNewlines)

        var exports: [String] = [
            "export COLORTERM=\(shellQuote(colorTerm))",
            "export TERM_PROGRAM=\(shellQuote(termProgram))",
        ]
        if !termProgramVersion.isEmpty {
            exports.append("export TERM_PROGRAM_VERSION=\(shellQuote(termProgramVersion))")
        }
        if !trimmedShellFeatures.isEmpty {
            exports.append("export GHOSTTY_SHELL_FEATURES=\(shellQuote(trimmedShellFeatures))")
        }
        return exports
    }

    private static func relayWarmupLines(remoteRelayPort: Int) -> [String] {
        guard remoteRelayPort > 0 else {
            return []
        }
        return [
            "mosaic_relay_cli=\"${MOSAIC_BUNDLED_CLI_PATH:-$HOME/.mosaic/bin/mosaic}\"",
            "if [ ! -x \"$mosaic_relay_cli\" ]; then mosaic_relay_cli=\"$(command -v mosaic 2>/dev/null || true)\"; fi",
            "mosaic_relay_tty=\"${MOSAIC_BOOTSTRAP_TTY:-}\"",
            "if [ -z \"$mosaic_relay_tty\" ]; then mosaic_relay_tty=\"$(tty 2>/dev/null || true)\"; fi",
            "mosaic_relay_tty=\"${mosaic_relay_tty##*/}\"",
            "if [ -n \"$mosaic_relay_tty\" ] && [ \"$mosaic_relay_tty\" != \"not a tty\" ]; then",
            "  mkdir -p \"$HOME/.mosaic/relay\" >/dev/null 2>&1 || true",
            "  printf '%s' \"$mosaic_relay_tty\" > \"$HOME/.mosaic/relay/\(remoteRelayPort).tty\" 2>/dev/null || true",
            "fi",
            "if [ -n \"$mosaic_relay_cli\" ] && [ -n \"$MOSAIC_WORKSPACE_ID\" ] && [ -n \"$mosaic_relay_tty\" ] && [ \"$mosaic_relay_tty\" != \"not a tty\" ]; then",
            "  (",
            "    mosaic_relay_report_tty=\"{\\\"workspace_id\\\":\\\"$MOSAIC_WORKSPACE_ID\\\",\\\"tty_name\\\":\\\"$mosaic_relay_tty\\\"}\"",
            "    mosaic_relay_ports_kick=\"{\\\"workspace_id\\\":\\\"$MOSAIC_WORKSPACE_ID\\\",\\\"reason\\\":\\\"command\\\"}\"",
            "    if [ -n \"$MOSAIC_SURFACE_ID\" ]; then",
            "      mosaic_relay_report_tty=\"{\\\"workspace_id\\\":\\\"$MOSAIC_WORKSPACE_ID\\\",\\\"surface_id\\\":\\\"$MOSAIC_SURFACE_ID\\\",\\\"tty_name\\\":\\\"$mosaic_relay_tty\\\"}\"",
            "      mosaic_relay_ports_kick=\"{\\\"workspace_id\\\":\\\"$MOSAIC_WORKSPACE_ID\\\",\\\"surface_id\\\":\\\"$MOSAIC_SURFACE_ID\\\",\\\"reason\\\":\\\"command\\\"}\"",
            "    fi",
            "    \"$mosaic_relay_cli\" rpc surface.report_tty \"$mosaic_relay_report_tty\" >/dev/null 2>&1 || true",
            "    \"$mosaic_relay_cli\" rpc surface.ports_kick \"$mosaic_relay_ports_kick\" >/dev/null 2>&1 || true",
            "  ) </dev/null >/dev/null 2>&1 &",
            "fi",
            "unset MOSAIC_BOOTSTRAP_TTY mosaic_relay_cli mosaic_relay_tty mosaic_relay_report_tty mosaic_relay_ports_kick",
        ]
    }

    private static func shellStateDirForRemoteRelayPort(_ remoteRelayPort: Int) -> String {
        "$HOME/.mosaic/relay/\(max(remoteRelayPort, 0)).shell"
    }

    private static func normalizedEnvValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shellQuote(_ value: String) -> String {
        let safePattern = "^[A-Za-z0-9_@%+=:,./-]+$"
        if value.range(of: safePattern, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
