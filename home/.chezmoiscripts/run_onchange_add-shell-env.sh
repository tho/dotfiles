#!/bin/sh
set -eu

# Expand HOME when the shell reads the startup file, not while installing it.
# shellcheck disable=SC2016
line='[ ! -f "$HOME/.config/shell/env.sh" ] || . "$HOME/.config/shell/env.sh"'

for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.zshenv" "$HOME/.zprofile" /etc/sandbox-persistent.sh; do
    # Do not create files that would shadow .profile or belong to the system.
    case "$profile" in
        "$HOME/.bash_profile"|"$HOME/.bash_login"|"$HOME/.zprofile"|/etc/sandbox-persistent.sh)
            [ -f "$profile" ] || continue ;;
    esac

    if ! grep -Fqx "$line" "$profile" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$profile"
    fi
done
