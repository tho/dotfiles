#!/bin/sh
set -eu

line='[ ! -f "$HOME/.config/shell/env.sh" ] || . "$HOME/.config/shell/env.sh"'

for profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zprofile"; do
    [ -f "$profile" ] || continue
    if ! grep -Fqx "$line" "$profile"; then
        printf '\n%s\n' "$line" >> "$profile"
    fi
done
