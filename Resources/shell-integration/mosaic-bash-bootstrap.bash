# mosaic bash prompt bootstrap.
#
# macOS ships /bin/bash 3.2, where Ghostty's automatic bash integration is
# unsupported and HOME-based wrapper startup is not reliable. mosaic instead
# exports this script as PROMPT_COMMAND so it runs once on the first interactive
# prompt: it sources mosaic's bash integration and then hands control to
# _mosaic_prompt_command.
#
# COMPOSE, don't clobber. A user's startup files may have appended their own
# command to PROMPT_COMMAND *after* this bootstrap before the first prompt --
# most notably `eval "$(starship init bash)"`, which appends starship_precmd.
# We must remove only this bootstrap and keep whatever the user appended, so
# hooks like starship_precmd keep running on every prompt instead of being wiped
# after the first one (https://github.com/emergent-inc/mosaic/issues/5164).
#
# How: strip everything up to and including the marker at the end of this script
# (the marker is the last occurrence, so the greedy ## match lands on it), which
# leaves exactly the user's appended tail. Then trim the leading separator and
# let mosaic-bash-integration.bash's PROMPT_COMMAND merge prepend _mosaic_prompt_command.
#
# This file is the single source of truth. Sources/GhosttyTerminalView.swift
# reads it (stripping these comments) and exports it as PROMPT_COMMAND, and
# tests/test_issue_5164_starship_prompt_composition.py exercises it.
#
# INJECTION CONSTRAINT: the app and the test both drop full-line `#` comments and
# blank lines before exporting this as PROMPT_COMMAND (so users never see a wall
# of comments in $PROMPT_COMMAND). Such lines are bash comments anyway, so this is
# behavior-preserving -- but every executable line below must stand on its own and
# must not begin with `#` (no full-line comments interleaved in the body).
PROMPT_COMMAND="${PROMPT_COMMAND##*__mosaic_bash_bootstrap_marker__}"
while [[ "$PROMPT_COMMAND" == [[:space:]\;]* ]]; do PROMPT_COMMAND="${PROMPT_COMMAND#?}"; done
if [[ "${MOSAIC_LOAD_GHOSTTY_BASH_INTEGRATION:-0}" == "1" && -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    _mosaic_ghostty_bash="$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
    [[ -r "$_mosaic_ghostty_bash" ]] && source "$_mosaic_ghostty_bash"
fi
if [[ "${MOSAIC_SHELL_INTEGRATION:-1}" != "0" && -n "${MOSAIC_SHELL_INTEGRATION_DIR:-}" ]]; then
    _mosaic_bash_integration="$MOSAIC_SHELL_INTEGRATION_DIR/mosaic-bash-integration.bash"
    [[ -r "$_mosaic_bash_integration" ]] && source "$_mosaic_bash_integration"
fi
unset _mosaic_ghostty_bash _mosaic_bash_integration
if declare -F _mosaic_prompt_command >/dev/null 2>&1; then _mosaic_prompt_command; fi
: __mosaic_bash_bootstrap_marker__
