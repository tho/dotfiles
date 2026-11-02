#!/bin/sh
set -eu

# Expose hunk's bundled review skill to coding agents. Runs on every apply so the
# links follow hunk upgrades (e.g. Homebrew's versioned Cellar path).
command -v hunk >/dev/null || exit 0

skill_file=$(hunk skill path hunk-review 2>/dev/null) || exit 0
skill_dir=$(dirname -- "$skill_file")
[ -f "$skill_dir/SKILL.md" ] || exit 0

# ~/.claude/skills: Claude Code. ~/.agents/skills: Codex and pi.
for skills in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    dest="$skills/hunk-review"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        printf 'Not replacing non-symlink: %s\n' "$dest" >&2
        continue
    fi
    [ "$(readlink -- "$dest" 2>/dev/null || true)" = "$skill_dir" ] && continue
    mkdir -p -- "$skills"
    ln -sfn -- "$skill_dir" "$dest"
done
