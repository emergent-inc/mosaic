# mosaic shell integration for fish
# Injected automatically, do not source manually.

set -l _mosaic_integration_enabled 1
if set -q MOSAIC_SHELL_INTEGRATION; and test "$MOSAIC_SHELL_INTEGRATION" = 0
    set _mosaic_integration_enabled 0
end

if test "$_mosaic_integration_enabled" != 0
    set -g _MOSAIC_SEND_TOOL ""
    if command -sq ncat
        set -g _MOSAIC_SEND_TOOL ncat
    else if command -sq socat
        set -g _MOSAIC_SEND_TOOL socat
    else if command -sq nc
        set -g _MOSAIC_SEND_TOOL nc
    end

    set -g _MOSAIC_SHELL_ACTIVITY_LAST ""
    set -g _MOSAIC_PORTS_LAST_RUN 0
    set -g _MOSAIC_TTY_NAME ""
    set -g _MOSAIC_TTY_REPORTED 0
    set -g _MOSAIC_PWD_LAST_PWD ""

    function _mosaic_now
        if test -n "$EPOCHSECONDS"
            printf '%s\n' "$EPOCHSECONDS"
        else
            date +%s
        end
    end

    function _mosaic_socket_is_unix
        test -n "$MOSAIC_SOCKET_PATH"; and test -S "$MOSAIC_SOCKET_PATH"
    end

    function _mosaic_relay_cli_path
        if test -n "$MOSAIC_BUNDLED_CLI_PATH"; and test -x "$MOSAIC_BUNDLED_CLI_PATH"
            printf '%s\n' "$MOSAIC_BUNDLED_CLI_PATH"
            return 0
        end
        command -v mosaic 2>/dev/null
    end

    function _mosaic_socket_uses_remote_relay
        test -n "$MOSAIC_SOCKET_PATH"; or return 1
        string match -q '/*' -- "$MOSAIC_SOCKET_PATH"; and return 1
        string match -q '*:*' -- "$MOSAIC_SOCKET_PATH"; or return 1
        set -l relay_cli (_mosaic_relay_cli_path)
        test -n "$relay_cli"
    end

    function _mosaic_send --argument-names payload
        test -n "$payload"; or return 0
        test -n "$MOSAIC_SOCKET_PATH"; or return 0
        switch "$_MOSAIC_SEND_TOOL"
            case ncat
                printf '%s\n' "$payload" | ncat -w 1 -U "$MOSAIC_SOCKET_PATH" --send-only >/dev/null 2>&1
            case socat
                printf '%s\n' "$payload" | socat -T 1 - "UNIX-CONNECT:$MOSAIC_SOCKET_PATH" >/dev/null 2>&1
            case nc
                printf '%s\n' "$payload" | nc -N -U "$MOSAIC_SOCKET_PATH" >/dev/null 2>&1; or printf '%s\n' "$payload" | nc -w 1 -U "$MOSAIC_SOCKET_PATH" >/dev/null 2>&1
        end
    end

    function _mosaic_send_bg --argument-names payload
        _mosaic_send "$payload" >/dev/null 2>&1 &
    end

    function _mosaic_json_escape --argument-names value
        set -l backslash "\\"
        set -l escaped_backslash "\\\\"
        set -l quote '"'
        set -l escaped_quote '\"'
        string replace -a "$backslash" "$escaped_backslash" -- "$value" \
            | string replace -a "$quote" "$escaped_quote" \
            | string replace -a (printf '\n') "\\n" \
            | string replace -a (printf '\r') "\\r" \
            | string replace -a (printf '\t') "\\t"
    end

    function _mosaic_relay_workspace_id
        if test -n "$MOSAIC_WORKSPACE_ID"
            printf '%s\n' "$MOSAIC_WORKSPACE_ID"
            return 0
        end
        test -n "$MOSAIC_TAB_ID"; or return 1
        printf '%s\n' "$MOSAIC_TAB_ID"
    end

    function _mosaic_relay_rpc_bg --argument-names method params
        _mosaic_socket_uses_remote_relay; or return 1
        set -l relay_cli (_mosaic_relay_cli_path)
        test -n "$relay_cli"; or return 1
        "$relay_cli" rpc "$method" "$params" >/dev/null 2>&1 &
    end

    function _mosaic_report_tty_via_relay
        _mosaic_socket_uses_remote_relay; or return 1
        test -n "$_MOSAIC_TTY_NAME"; or return 1
        set -l workspace_id (_mosaic_relay_workspace_id); or return 1
        set -l tty_name_json (_mosaic_json_escape "$_MOSAIC_TTY_NAME")
        set -l params "{\"workspace_id\":\"$workspace_id\",\"tty_name\":\"$tty_name_json\""
        if test -n "$MOSAIC_PANEL_ID"
            set params "$params,\"surface_id\":\"$MOSAIC_PANEL_ID\""
        end
        set params "$params}"
        _mosaic_relay_rpc_bg surface.report_tty "$params"
    end

    function _mosaic_report_pwd_via_relay --argument-names pwd
        _mosaic_socket_uses_remote_relay; or return 1
        test -n "$pwd"; or return 1
        set -l workspace_id (_mosaic_relay_workspace_id); or return 1
        set -l pwd_json (_mosaic_json_escape "$pwd")
        set -l params "{\"workspace_id\":\"$workspace_id\",\"path\":\"$pwd_json\""
        if test -n "$MOSAIC_PANEL_ID"
            set params "$params,\"surface_id\":\"$MOSAIC_PANEL_ID\""
        end
        set params "$params}"
        _mosaic_relay_rpc_bg surface.report_pwd "$params"
    end

    function _mosaic_ports_kick_via_relay --argument-names reason
        _mosaic_socket_uses_remote_relay; or return 1
        set -l workspace_id (_mosaic_relay_workspace_id); or return 1
        test -n "$reason"; or set reason command
        set -l params "{\"workspace_id\":\"$workspace_id\",\"reason\":\"$reason\""
        if test -n "$MOSAIC_PANEL_ID"
            set params "$params,\"surface_id\":\"$MOSAIC_PANEL_ID\""
        end
        set params "$params}"
        _mosaic_relay_rpc_bg surface.ports_kick "$params"
    end

    function _mosaic_path_prepend_unique_directory --argument-names directory
        test -n "$directory"; or return 0
        set -l next_path "$directory"
        for entry in $PATH
            test "$entry" = "$directory"; and continue
            set -a next_path "$entry"
        end
        set -gx PATH $next_path
    end

    function _mosaic_install_cli_command_shim --argument-names command_name wrapper_path
        set -l tmp_root /tmp
        if set -q TMPDIR; and test -n "$TMPDIR"
            set tmp_root "$TMPDIR"
        end
        set -l surface_component "$fish_pid"
        if set -q MOSAIC_SURFACE_ID; and test -n "$MOSAIC_SURFACE_ID"
            set surface_component "$MOSAIC_SURFACE_ID"
        end
        set -l shim_root "$tmp_root/mosaic-cli-shims/$surface_component"
        set -l shim_path "$shim_root/$command_name"
        mkdir -p "$shim_root" >/dev/null 2>&1; or return 0
        begin
            printf '%s\n' '#!/usr/bin/env bash'
            if test "$command_name" = claude
                printf 'mosaic_wrapper=%s\n' (string escape --style=script -- "$wrapper_path")
                printf '%s\n' 'if [[ ! -x "$mosaic_wrapper" && -n "${MOSAIC_BUNDLED_CLI_PATH:-}" ]]; then'
                printf '%s\n' '    mosaic_candidate="$(dirname "$MOSAIC_BUNDLED_CLI_PATH")/mosaic-claude-wrapper"'
                printf '%s\n' '    if [[ -x "$mosaic_candidate" ]]; then'
                printf '%s\n' '        mosaic_wrapper="$mosaic_candidate"'
                printf '%s\n' '    fi'
                printf '%s\n' 'fi'
                printf '%s\n' 'if [[ ! -x "$mosaic_wrapper" ]]; then'
                printf '%s\n' '    mosaic_cli="$(command -v mosaic 2>/dev/null || true)"'
                printf '%s\n' '    if [[ -n "$mosaic_cli" ]]; then'
                printf '%s\n' '        mosaic_candidate="$(dirname "$mosaic_cli")/mosaic-claude-wrapper"'
                printf '%s\n' '        if [[ -x "$mosaic_candidate" ]]; then'
                printf '%s\n' '            mosaic_wrapper="$mosaic_candidate"'
                printf '%s\n' '        fi'
                printf '%s\n' '    fi'
                printf '%s\n' 'fi'
                printf 'export MOSAIC_CLAUDE_WRAPPER_SHIM=%s\n' (string escape --style=script -- "$shim_path")
                printf 'export MOSAIC_CLAUDE_WRAPPER_SHIM_ROOT=%s\n' (string escape --style=script -- "$shim_root")
                printf '%s\n' 'if [[ -x "$mosaic_wrapper" ]]; then'
                printf '%s\n' '    exec "$mosaic_wrapper" "$@"'
                printf '%s\n' 'fi'
                printf '%s\n' 'mosaic_path_without_shim=""'
                printf '%s\n' 'mosaic_old_ifs="$IFS"'
                printf '%s\n' 'IFS=:'
                printf '%s\n' 'for mosaic_entry in ${PATH:-}; do'
                printf '%s\n' '    if [[ "$mosaic_entry" == "$MOSAIC_CLAUDE_WRAPPER_SHIM_ROOT" || "$mosaic_entry" == */mosaic-cli-shims/* || "$mosaic_entry" == */mosaic-cli-shims ]]; then'
                printf '%s\n' '        continue'
                printf '%s\n' '    fi'
                printf '%s\n' '    if [[ -z "$mosaic_path_without_shim" ]]; then'
                printf '%s\n' '        mosaic_path_without_shim="$mosaic_entry"'
                printf '%s\n' '    else'
                printf '%s\n' '        mosaic_path_without_shim="$mosaic_path_without_shim:$mosaic_entry"'
                printf '%s\n' '    fi'
                printf '%s\n' 'done'
                printf '%s\n' 'IFS="$mosaic_old_ifs"'
                printf '%s\n' 'export PATH="$mosaic_path_without_shim"'
                printf '%s\n' 'exec claude "$@"'
            else
                printf 'exec %s "$@"\n' (string escape --style=script -- "$wrapper_path")
            end
        end >"$shim_path" 2>/dev/null; or return 0
        chmod 0700 "$shim_path" >/dev/null 2>&1; or return 0
        if test "$command_name" = claude
            set -gx MOSAIC_CLAUDE_WRAPPER_SHIM "$shim_path"
            set -gx MOSAIC_CLAUDE_WRAPPER_SHIM_ROOT "$shim_root"
        end
        _mosaic_path_prepend_unique_directory "$shim_root"
    end

    function _mosaic_install_cli_wrapper --argument-names command_name wrapper_file
        test -n "$MOSAIC_SHELL_INTEGRATION_DIR"; or return 0
        set -l integration_dir (string replace -r '/$' '' -- "$MOSAIC_SHELL_INTEGRATION_DIR")
        set -l bundle_dir (string replace -r '/shell-integration$' '' -- "$integration_dir")
        set -l wrapper_path "$bundle_dir/bin/$wrapper_file"
        test -x "$wrapper_path"; or return 0

        if test "$command_name" = claude
            _mosaic_install_cli_command_shim "$command_name" "$wrapper_path"
        end
        functions -q "$command_name"; and return 0
        switch "$command_name"
            case claude
                function claude --wraps "$wrapper_path" --inherit-variable wrapper_path
                    if test -x "$MOSAIC_CLAUDE_WRAPPER_SHIM"
                        "$MOSAIC_CLAUDE_WRAPPER_SHIM" $argv
                    else if test -x "$wrapper_path"
                        "$wrapper_path" $argv
                    else
                        command claude $argv
                    end
                end
            case grok
                function grok --wraps "$wrapper_path" --inherit-variable wrapper_path
                    "$wrapper_path" $argv
                end
        end
    end

    _mosaic_install_cli_wrapper claude mosaic-claude-wrapper
    _mosaic_install_cli_wrapper grok grok

    function _mosaic_report_tty_once
        test "$_MOSAIC_TTY_REPORTED" = 1; and return 0
        if test -z "$_MOSAIC_TTY_NAME"
            set -g _MOSAIC_TTY_NAME (tty 2>/dev/null | string replace -r '^.*/' '')
        end
        test -n "$_MOSAIC_TTY_NAME"; or return 0
        test "$_MOSAIC_TTY_NAME" != "not a tty"; or return 0

        if _mosaic_socket_is_unix
            test -n "$MOSAIC_TAB_ID"; or return 0
            test -n "$MOSAIC_PANEL_ID"; or return 0
            set -g _MOSAIC_TTY_REPORTED 1
            _mosaic_send_bg "report_tty $_MOSAIC_TTY_NAME --tab=$MOSAIC_TAB_ID --panel=$MOSAIC_PANEL_ID"
        else if _mosaic_socket_uses_remote_relay
            set -g _MOSAIC_TTY_REPORTED 1
            _mosaic_report_tty_via_relay
        end
    end

    function _mosaic_report_shell_activity_state --argument-names state
        test -n "$state"; or return 0
        _mosaic_socket_is_unix; or return 0
        test -n "$MOSAIC_TAB_ID"; or return 0
        test -n "$MOSAIC_PANEL_ID"; or return 0
        test "$_MOSAIC_SHELL_ACTIVITY_LAST" = "$state"; and return 0
        set -g _MOSAIC_SHELL_ACTIVITY_LAST "$state"
        _mosaic_send_bg "report_shell_state $state --tab=$MOSAIC_TAB_ID --panel=$MOSAIC_PANEL_ID"
    end

    function _mosaic_reset_terminal_keyboard_protocols
        isatty stdout; or test -n "$MOSAIC_TEST_FORCE_KEYBOARD_RESET$MOSAIC_TEST_FORCE_KITTY_RESET"; or return 0
        printf '\033[>m\033[<8u\033[?9l\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l\033[?1004l\033[?2004l\033[?2026l'
    end

    function _mosaic_ports_kick --argument-names reason
        test -n "$reason"; or set reason command
        test -n "$MOSAIC_TAB_ID"; or return 0
        set -g _MOSAIC_PORTS_LAST_RUN (_mosaic_now)
        if _mosaic_socket_is_unix
            test -n "$MOSAIC_PANEL_ID"; or return 0
            _mosaic_send_bg "ports_kick --tab=$MOSAIC_TAB_ID --panel=$MOSAIC_PANEL_ID --reason=$reason"
        else
            _mosaic_ports_kick_via_relay "$reason"
        end
    end

    function _mosaic_preexec --on-event fish_preexec
        _mosaic_report_tty_once
        _mosaic_report_shell_activity_state running
        _mosaic_ports_kick command
    end

    function _mosaic_prompt --on-event fish_prompt
        _mosaic_reset_terminal_keyboard_protocols
        _mosaic_report_tty_once
        _mosaic_report_shell_activity_state prompt
        set -l pwd "$PWD"
        if test "$pwd" != "$_MOSAIC_PWD_LAST_PWD"
            if _mosaic_socket_is_unix
                if test -n "$MOSAIC_TAB_ID"; and test -n "$MOSAIC_PANEL_ID"
                    set -l qpwd (_mosaic_json_escape "$pwd")
                    if _mosaic_send_bg "report_pwd \"$qpwd\" --tab=$MOSAIC_TAB_ID --panel=$MOSAIC_PANEL_ID"
                        set -g _MOSAIC_PWD_LAST_PWD "$pwd"
                    end
                end
            else if _mosaic_report_pwd_via_relay "$pwd"
                set -g _MOSAIC_PWD_LAST_PWD "$pwd"
            end
        end
        set -l now (_mosaic_now)
        if test (math "$now - $_MOSAIC_PORTS_LAST_RUN") -ge 5
            _mosaic_ports_kick refresh
        end
    end
end

set -l _mosaic_user_config_home ""
if set -q MOSAIC_FISH_CONFIG_HOME
    set _mosaic_user_config_home "$MOSAIC_FISH_CONFIG_HOME"
else if set -q HOME
    set _mosaic_user_config_home "$HOME/.config"
end

set -l _mosaic_user_config "$_mosaic_user_config_home/fish/config.fish"
if not set -q MOSAIC_FISH_USER_CONFIG_ALREADY_LOADED; and test -n "$_mosaic_user_config_home"; and test "$_mosaic_user_config_home" != "$XDG_CONFIG_HOME"
    set -gx XDG_CONFIG_HOME "$_mosaic_user_config_home"

    set -l _mosaic_user_functions "$_mosaic_user_config_home/fish/functions"
    if test -d "$_mosaic_user_functions"; and not contains -- "$_mosaic_user_functions" $fish_function_path
        set -g fish_function_path "$_mosaic_user_functions" $fish_function_path
    end

    set -l _mosaic_user_completions "$_mosaic_user_config_home/fish/completions"
    if test -d "$_mosaic_user_completions"; and not contains -- "$_mosaic_user_completions" $fish_complete_path
        set -g fish_complete_path "$_mosaic_user_completions" $fish_complete_path
    end

    for _mosaic_user_conf in "$_mosaic_user_config_home"/fish/conf.d/*.fish
        if test -r "$_mosaic_user_conf"
            source "$_mosaic_user_conf"
        end
    end

    if test -r "$_mosaic_user_config"
        source "$_mosaic_user_config"
    end
end
