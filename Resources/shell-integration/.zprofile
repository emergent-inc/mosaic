# vim:ft=zsh
#
# Compatibility shim: with the current integration model, mosaic restores
# ZDOTDIR in .zshenv so this file should never be reached. If it is, restore
# ZDOTDIR and behave like vanilla zsh by sourcing the user's .zprofile.

if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
    builtin unset GHOSTTY_ZSH_ZDOTDIR
elif [[ -n "${MOSAIC_ZSH_ZDOTDIR+X}" ]]; then
    builtin export ZDOTDIR="$MOSAIC_ZSH_ZDOTDIR"
    builtin unset MOSAIC_ZSH_ZDOTDIR
else
    builtin unset ZDOTDIR
fi

builtin typeset _mosaic_file="${ZDOTDIR-$HOME}/.zprofile"
[[ ! -r "$_mosaic_file" ]] || builtin source -- "$_mosaic_file"
builtin unset _mosaic_file
