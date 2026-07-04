import Foundation

extension DockSplitStore {
    static func resolvedWorkingDirectory(_ cwd: String?, baseDirectory: String) -> String {
        guard let cwd, !cwd.isEmpty else { return baseDirectory }
        if cwd.hasPrefix("/") {
            return cwd
        }
        return (baseDirectory as NSString).appendingPathComponent(cwd)
    }

    static func shellStartupScript(command: String, workingDirectory: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent(
            "mosaic-dock-control-\(UUID().uuidString.lowercased()).sh"
        )
        let encodedCommand = Data(command.utf8).base64EncodedString()
        let encodedWorkingDirectory = Data(workingDirectory.utf8).base64EncodedString()
        let body = """
        #!/bin/sh
        mosaic_dock_decode() { printf '%s' "$1" | base64 --decode 2>/dev/null || printf '%s' "$1" | base64 -D 2>/dev/null; }
        mosaic_dock_login_shell() {
          mosaic_dock_user="$(id -un 2>/dev/null || printf '%s' "${USER:-}")"
          mosaic_dock_ds_shell="$(dscl . -read "/Users/$mosaic_dock_user" UserShell 2>/dev/null | awk '{print $2; exit}')"
          if [ -n "$mosaic_dock_ds_shell" ] && [ -x "$mosaic_dock_ds_shell" ]; then printf '%s\\n' "$mosaic_dock_ds_shell"
          elif [ -n "${SHELL:-}" ] && [ -x "${SHELL:-}" ]; then printf '%s\\n' "$SHELL"
          else printf '%s\\n' /bin/sh; fi
        }
        mosaic_dock_command="$(mosaic_dock_decode '\(encodedCommand)')"
        mosaic_dock_working_directory="$(mosaic_dock_decode '\(encodedWorkingDirectory)')"
        mosaic_dock_shell="$(mosaic_dock_login_shell)"
        mosaic_dock_bundle_bin=""
        if [ -n "${MOSAIC_BUNDLED_CLI_PATH:-}" ]; then mosaic_dock_bundle_bin="$(dirname "$MOSAIC_BUNDLED_CLI_PATH")"; fi
        export SHELL="$mosaic_dock_shell"
        rm -f -- "$0" 2>/dev/null || true
        case "$(basename "$mosaic_dock_shell")" in
          fish)
            MOSAIC_DOCK_BUNDLE_BIN="$mosaic_dock_bundle_bin" MOSAIC_DOCK_START_COMMAND="$mosaic_dock_command" MOSAIC_DOCK_START_DIRECTORY="$mosaic_dock_working_directory" "$mosaic_dock_shell" -l -c 'if test -n "$MOSAIC_DOCK_BUNDLE_BIN"; and not contains -- "$MOSAIC_DOCK_BUNDLE_BIN" $PATH; set -gx PATH "$MOSAIC_DOCK_BUNDLE_BIN" $PATH; end; if test -n "$MOSAIC_DOCK_START_DIRECTORY"; cd "$MOSAIC_DOCK_START_DIRECTORY"; end; eval "$MOSAIC_DOCK_START_COMMAND"'
            ;;
          *) MOSAIC_DOCK_BUNDLE_BIN="$mosaic_dock_bundle_bin" MOSAIC_DOCK_START_COMMAND="$mosaic_dock_command" MOSAIC_DOCK_START_DIRECTORY="$mosaic_dock_working_directory" "$mosaic_dock_shell" -lc 'if [ -n "${MOSAIC_DOCK_BUNDLE_BIN:-}" ]; then case ":${PATH:-}:" in *":$MOSAIC_DOCK_BUNDLE_BIN:"*) ;; *) PATH="$MOSAIC_DOCK_BUNDLE_BIN${PATH:+:$PATH}"; export PATH ;; esac; fi; cd "$MOSAIC_DOCK_START_DIRECTORY" 2>/dev/null || true; eval "$MOSAIC_DOCK_START_COMMAND"'
            ;;
        esac
        printf '\\n'
        exec "$mosaic_dock_shell" -l
        """
        do {
            try body.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            return scriptURL.path
        } catch {
            return "/bin/sh"
        }
    }
}
