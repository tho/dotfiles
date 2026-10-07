# Adding software

- Support both Ubuntu/Debian and macOS unless explicitly told otherwise.
- Add apt/Homebrew package names to the alphabetically sorted lists in `home/.chezmoiscripts/{linux,darwin}/run_onchange_before_install-packages.sh.tmpl`.
- For tools unavailable from the package manager, follow `run_onchange_before_install-<tool>.sh.tmpl`; ensure dependencies install before consumers.
- Validate template rendering and shell syntax for both platforms. Do not run installers just to test changes.
