# Project documentation

Preserve the repository's structure and write for the relevant reader. Add README sections only when they carry verified information.

## Setup and contribution

Derive module and command paths from source, build configuration, and releases. Distinguish adding an importable library with `go get` from installing a command with `go install <command-path>@<version>`. Check major-version path suffixes, supported platforms, Go requirements, and available release assets. Document only distribution channels the project actually maintains.

Check build, test, lint, and generator instructions against current scripts, Make targets, CI and tool versions. Verify working directories, prerequisites, build tags, and environment assumptions. Prefer non-mutating verification commands over automatic fixer commands in a routine check. Existing license files and policy establish license claims; a template is not authority to declare MIT or create a license.

Contribution instructions should let a newcomer reproduce the supported local workflow.

## Changelogs and release notes

Use the project's format, such as Keep a Changelog or existing release notes. Derive entries from the requested diff, commits, release boundary, or supplied facts. Explain the user-visible change with the same scope as the evidence. A fix for one edge case is not a general reliability claim. Preserve migration requirements and breaking changes; do not invent tags, release dates, removal timelines, benchmarks, or security impact.

## Sites and AI indexes

For requested sites, use existing tooling, navigation, versions, and source-of-truth files, and run their build and link checks when practical.

Treat `llms.txt` as an optional index of verified documentation and useful entry points, not a second API specification to keep in sync. Link to authoritative docs rather than duplicating detailed contracts. Check local paths and anchors; report external links that could not be verified.
