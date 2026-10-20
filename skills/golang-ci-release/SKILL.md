---
name: golang-ci-release
description: 'Builds and reviews Go CI and release automation. Use when creating or fixing GitHub Actions workflows (.github/workflows) for tests, lint, security scans, build matrices, scheduled dependency checks, release tags, GoReleaser, or container publishing. Not for configuring a local linter (golang-lint), upgrading one dependency (golang-dependencies), writing tests (golang-testing), or diagnosing application failures (golang-debugging).'
---

# Go CI and Release

Give maintainers automation they can review and trust: checks matched to the project, failures that propagate to the required status, and releases built from the validated revision. Adapt existing workflows before adding parallel machinery.

## Pipeline contract

Establish the Go support policy, module/workspace boundaries, existing checks, runner capabilities and release outputs. A module's Go minimum does not define the full support policy. Verify action, tool and runner compatibility upstream before choosing versions.

For each job, make the triggering event, checked revision, failure condition and permissions explicit. Keep untrusted PR code and experimental dependencies away from release credentials and trusted caches. A green job that skipped its check, swallowed an exit status, or tested another revision is not a quality gate.

## Dependency default

Prefer scheduled vulnerability scans of committed dependencies and separate tests against newer compatible dependencies. Keep experimental upgrades disposable. Do not add Dependabot, Renovate, automatic version-bump PRs or auto-merge unless requested. Adopt upgrades deliberately on the project's development schedule; applicable vulnerabilities still need timely impact assessment and remediation.

## Focused guidance

Read the relevant reference before producing its workflow. Adapt only the needed templates.

| Decision | Reference |
| --- | --- |
| Test, lint, scan and build checks; module and toolchain coverage | [Checks](references/checks.md) |
| Events, permissions, credentials, cache isolation and action pins | [Workflow security](references/workflow-security.md) |
| Scheduled scanning, newer-dependency experiments and upgrade policy | [Dependencies](references/dependencies.md) |
| Tag validation, libraries, GoReleaser, binaries and containers | [Releases](references/releases.md) |

Templates: [CI](assets/ci.yml), [vulnerability scan](assets/govulncheck.yml), [dependency compatibility](assets/dependency-compatibility.yml), [binary release](assets/release.yml), [GoReleaser](assets/goreleaser.yml), and [container](assets/container.yml). Optional application skills: `golang-testing`, `golang-security`, and `golang-debugging`. None is required.

## Verification and handoff

Validate workflow syntax with `actionlint`, release configuration with `goreleaser check` and a snapshot, and executed commands with a deliberately failing fixture that proves the job goes red. Release evidence must identify the validated tag commit.

Report the changed behavior, checks actually run and results, and remaining host-side settings or credentials. Distinguish static validation and local dry runs from execution on GitHub. Publishing or changing repository settings requires authorization.
