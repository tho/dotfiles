---
name: golang-maintenance
description: 'Maintains existing Go code through behavior-preserving refactoring and version-driven modernization. Use when refactoring Go code, renaming symbols across callers with gopls, extracting or inlining functions, moving or splitting packages behind type aliases, planning staged refactors, bumping the go.mod go or toolchain directive, replacing deprecated APIs, applying go fix or modernize analyzers, or adopting idioms for a target Go release. Not for choosing names (golang-conventions), greenfield architecture (golang-design), repository or module layout (golang-project-setup), dependency-only upgrades (golang-dependencies), CI workflows (golang-ci-release), diagnosing failures (golang-debugging), or performance tuning (golang-performance-engineering).'
---

# Go Maintenance

Produce a maintenance plan or verified change that a maintainer can review without this conversation: affected callers, compatibility promises, ordered changes, and evidence for behavior preservation or explicitly intended differences.

## Choose the path

- **Behavior-preserving refactoring:** load [refactoring](references/refactoring.md). Keep externally observable behavior and the supported Go versions fixed.
- **Go-version-driven modernization:** load [modernization](references/modernization.md) and the relevant rows in [version migrations](references/version-migrations.md). Establish the supported version range before choosing replacements.
- **Mixed requests:** load both path references and separate structural steps from version/API migrations. Order by actual dependencies; a language feature prerequisite can precede the refactor that needs it.

For either path, load [verification](references/verification.md) before editing or writing an advisory plan. Load [tooling](references/tooling.md) when mapping symbols or applying automated rewrites.

## Shared contract

Match the requested mode: advice or review produces findings; execution produces changes and verification. Keep incidental opportunities outside the authorized scope as optional notes.

Honor existing authorization; clarify unresolved compatibility choices such as dropping an older Go version or removing exported API. Leave commits, PR publication and merges to the user unless they ask.

Classify each change as structural, version/API migration, or behavioral. Separate bug fixes and optimizations from structural changes even when they touch the same function. Semantic tooling does not prove reflection, serialization or external callers unchanged.

When the request also chooses names, architecture or package boundaries, keep that decision distinct from the migration mechanics applied here: compatibility bridges, caller migration and verification.

## Completion

Give the maintainer the changed scope, retained or changed compatibility, checks actually run with toolchain versions, remaining failures or unavailable checks, and any staged work still outstanding. An advisory plan names the verification required; it does not claim those checks ran.
