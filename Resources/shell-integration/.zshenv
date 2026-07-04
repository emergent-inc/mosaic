# vim:ft=zsh
#
# mosaic ZDOTDIR bootstrap for zsh.
#
# GhosttyKit already uses a ZDOTDIR injection mechanism for zsh (setting ZDOTDIR
# to Ghostty's integration dir). mosaic also needs to run its integration, but
# we must restore the user's real ZDOTDIR immediately so that:
# - /etc/zshrc sets HISTFILE relative to the real ZDOTDIR/HOME (shared history)
# - zsh loads the user's real .zprofile/.zshrc normally (no wrapper recursion)
#
# We restore ZDOTDIR from (in priority order):
# - GHOSTTY_ZSH_ZDOTDIR (set by GhosttyKit when it overwrote ZDOTDIR)
# - MOSAIC_ZSH_ZDOTDIR (set by mosaic when it overwrote a user-provided ZDOTDIR)
# - unset (zsh treats unset ZDOTDIR as $HOME)

if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
    builtin unset GHOSTTY_ZSH_ZDOTDIR
elif [[ -n "${MOSAIC_ZSH_ZDOTDIR+X}" \
   && "$MOSAIC_ZSH_ZDOTDIR" != "${MOSAIC_SHELL_INTEGRATION_DIR:-}" \
   && "$MOSAIC_ZSH_ZDOTDIR" != */Contents/Resources/shell-integration ]]; then
    builtin export ZDOTDIR="$MOSAIC_ZSH_ZDOTDIR"
    builtin unset MOSAIC_ZSH_ZDOTDIR
else
    builtin unset ZDOTDIR
    builtin unset MOSAIC_ZSH_ZDOTDIR
fi

{
    # zsh treats unset ZDOTDIR as if it were HOME. We do the same.
    builtin typeset _mosaic_file="${ZDOTDIR-$HOME}/.zshenv"
    [[ ! -r "$_mosaic_file" ]] || builtin source -- "$_mosaic_file"

    if [[ -o interactive \
       && -z "${ZSH_EXECUTION_STRING:-}" \
       && "${MOSAIC_SHELL_INTEGRATION:-1}" != "0" \
       && -n "${MOSAIC_SHELL_INTEGRATION_DIR:-}" \
       && -r "${MOSAIC_SHELL_INTEGRATION_DIR}/mosaic-zsh-integration.zsh" \
       && "${TERM:-}" == "xterm-256color" \
       && -z "${MOSAIC_ZSH_RESTORE_TERM:-}" ]]; then
        # Keep startup TERM-compatible prompt/theme selection during shell init,
        # then restore the managed xterm-256color identity before the first
        # interactive command executes.
        builtin export MOSAIC_ZSH_RESTORE_TERM="$TERM"
        builtin export TERM="xterm-ghostty"
        builtin typeset -g _MOSAIC_DELAY_TERM_RESTORE_UNTIL_FIRST_PROMPT=1
    fi
} always {
    if [[ -o interactive ]]; then
        # We overwrote GhosttyKit's injected ZDOTDIR, so manually load Ghostty's
        # zsh integration if available.
        #
        # We can't rely on GHOSTTY_ZSH_ZDOTDIR here because Ghostty's own zsh
        # bootstrap unsets it before chaining into this mosaic wrapper.
        if [[ "${MOSAIC_LOAD_GHOSTTY_ZSH_INTEGRATION:-0}" == "1" ]]; then
            if [[ -n "${MOSAIC_SHELL_INTEGRATION_DIR:-}" ]]; then
                builtin typeset _mosaic_ghostty="$MOSAIC_SHELL_INTEGRATION_DIR/ghostty-integration.zsh"
            fi
            if [[ ! -r "${_mosaic_ghostty:-}" && -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
                builtin typeset _mosaic_ghostty="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
            fi
            [[ -r "$_mosaic_ghostty" ]] && builtin source -- "$_mosaic_ghostty"
        fi

        # Load mosaic integration (unless disabled)
        if [[ "${MOSAIC_SHELL_INTEGRATION:-1}" != "0" && -n "${MOSAIC_SHELL_INTEGRATION_DIR:-}" ]]; then
            builtin typeset _mosaic_integ="$MOSAIC_SHELL_INTEGRATION_DIR/mosaic-zsh-integration.zsh"
            [[ -r "$_mosaic_integ" ]] && builtin source -- "$_mosaic_integ"
        fi
    fi

    builtin unset _mosaic_file _mosaic_ghostty _mosaic_integ
}
