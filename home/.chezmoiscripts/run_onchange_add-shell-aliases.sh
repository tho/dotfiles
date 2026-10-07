#!/bin/sh
set -eu

line='[ ! -f "$HOME/.config/shell/aliases.sh" ] || . "$HOME/.config/shell/aliases.sh"'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if ! grep -Fqx "$line" "$rc" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$rc"
    fi
done
