---
name: golang-dependencies
description: 'Manages Go module dependencies and their risks. Use when adding, removing or upgrading dependencies with go get, editing go.mod, go.sum or go.work requirements, running go mod tidy, explaining selected versions (MVS), resolving conflicts or forks with replace, exclude or retract, vendoring, fetching private modules (GOPRIVATE), pinning tools, or assessing dependency adoption, licenses and govulncheck-reported dependency CVEs. Not for Go-version upgrades or modernization (golang-maintenance), application security review (golang-security), repository or workspace layout (golang-project-setup), or CI workflow automation (golang-ci-release).'
---

# Go Dependencies

Produce dependency advice, findings, or a verified change that a maintainer can review without this conversation: selected versions, reasons, compatibility impact, dependency risk, and evidence for reproducibility are explicit.

Honor the requested mode and existing authorization. Advice or review does not imply edits or tool installation. For execution, keep the dependency scope and supported Go versions fixed unless the request authorizes changing them; surface unresolved package or compatibility choices before introducing them. Where the repository documents dependency policy (approved modules or licenses, update scope or cadence, vendoring, workspace, proxy settings, required scanners or checks), follow it over this skill's defaults and name it in the result.

## Focused references

Load the references relevant to the dependency decision.

| Concern | Reference |
| --- | --- |
| Add/remove, version selection, major paths, forks and conflicts | [Module changes](references/module-changes.md) |
| Targeted or bulk updates, migration impact and verification | [Upgrades](references/upgrades.md) |
| Checksums, tool versions, vendoring, private modules and workspaces | [Reproducibility](references/reproducibility.md) |
| Adoption, licenses, transitive footprint and dependency CVEs | [Dependency risk](references/dependency-risk.md) |

## Completion

Show the requested and actual module changes, including indirect changes and any toolchain requirement change. Derive them by capturing `go list -m all` and `go mod edit -json` before and after the change and diffing, rather than reading go.mod by eye. Report checks actually run, their scope and results, and unavailable evidence. For advice, name the checks still needed rather than claiming verification.
