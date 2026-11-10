# Shell compatibility

- Shell-specific changes should work in bash, fish, and zsh.

# Adding software

- Support both Ubuntu/Debian and macOS unless explicitly told otherwise.
- Ensure dependencies install before consumers.
- Add apt/Homebrew package names to the alphabetically sorted lists in `home/.chezmoiscripts/{linux,darwin}/run_onchange_before_install-packages.sh.tmpl`.
- On macOS, install every tool with Homebrew.
- On Linux, install tools that apt lacks as pinned `.chezmoiexternal.toml` entries: a release archive with a fixed version and per-arch `checksum.sha256`, not an install script.
- Do not make chezmoi itself depend on those tools (e.g. in `modify_` scripts): externals apply alphabetically alongside other targets, so they may not exist yet. Prefer chezmoi template functions or `jq`.
- Validate template rendering and shell syntax for both platforms. Do not run installers just to test changes.
