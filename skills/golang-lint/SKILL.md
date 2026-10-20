---
name: golang-lint
description: 'Configures and runs Go linters and formatters, interprets findings, and handles justified suppressions. Use when configuring or migrating .golangci.yml, choosing linters, configuring gofmt, gofumpt or goimports, running golangci-lint, go vet or staticcheck, troubleshooting lint failures, adopting linting on an existing codebase with a backlog of findings, or auditing //nolint directives. Not for naming or style judgment (golang-conventions), or CI workflow wiring (golang-ci-release).'
---

# Go Lint

Help Go maintainers reach a reproducible lint result: configuration that matches their toolchain, findings explained against the code, and narrow suppressions backed by evidence. Report the command, scope, result, and any remaining limitations so another maintainer can reproduce the conclusion.

Preserve the repository's existing lint policy unless the task calls for changing it. Match configuration and flags to the installed version and Go toolchain before editing.

## Guidance by task

- Read [configuration](references/configuration.md) for setup, linter selection, version migration, formatter configuration, and exclusion rules. The bundled [v2 configuration](assets/.golangci.yml) is a minimal starting point, not a policy to impose on an existing repository.
- Read [running and findings](references/running-and-findings.md) for package-scoped execution, interpreting diagnostics, troubleshooting analysis failures, and incremental adoption.
- Read [suppressions](references/suppressions.md) for justified exceptions, directive scope, and enforcing directive hygiene.

## Evidence of completion

A configuration change is complete when the installed tool accepts it and the intended checks run, or the missing tool or environment limitation is stated explicitly. A failed analysis or a clean filtered run is not evidence that the whole repository is clean. Preserve the distinction between findings, analysis failures, and findings hidden by filters.

Autofix and formatting are edits: use them within the requested scope, review the resulting diff, and do not run concurrent writers over the same files. Rerun the relevant lint scope after any fix, plus focused behavior checks when semantics changed.
