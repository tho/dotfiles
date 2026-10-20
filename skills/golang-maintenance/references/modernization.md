# Go-version-driven modernization

Produce a prioritized migration or verified patch tied to the project's supported Go range. A newer spelling or API is useful only when its availability and semantics fit that contract.

## Establish the version contract

Read each affected module's go directive, the workspace configuration, toolchain directives, build constraints, CI matrix, and stated consumer support (`go mod edit -json` per module and `go work edit -json` expose the Go, Toolchain and Godebug fields). Record the installed toolchain separately with `go env GOVERSION GOTOOLCHAIN`. A newer workspace or preferred toolchain does not automatically raise every module's language version or end support for an older compiler.

Default to retaining the existing minimum unless the request authorizes changing it. If the user asks for an upgrade, identify the intended target and support consequences from context. For "latest stable," verify the current stable release with official Go release information. When authoritative information or the target toolchain is unavailable, state that limitation and keep uncertain APIs out of applied changes.

Read the project's optional `.modernize` ignore file before scanning, in each affected module root and then the repository root. Each line is `<YYYY-MM-DD> <category> <reason>`, for example `2026-10-10 logging Keep the current logging backend for compatibility`; honor ignored categories and reasons. Append an explicitly declined suggestion in that format only when persistent ignore tracking is authorized; finding an opportunity does not by itself justify creating the file.

## Scope and priorities

For a local request, inspect only relevant code and immediate consumers. An explicit codebase scan may cover deprecated APIs, language constructs, standard library replacements, test APIs, and toolchain-coupled tooling. A scan returns candidates; it does not itself authorize sweeping writes, dependency changes, or CI automation.

For each candidate record current pattern, minimum release, prerequisite, observable differences, benefit, and verification. Prioritize required compatibility repairs, then improvements with clear correctness value, then readability. Optional infrastructure changes and PGO need their own justification.

## Apply by semantics

| Class | Treatment |
| --- | --- |
| Same behavior, newer syntax | Apply within scope only after confirming the module language version and expression semantics. Keep the patch mechanical. |
| New API with different defaults or lifetime | Treat as a semantic migration. Identify preserved and intentionally changed contracts, then add focused compatibility tests. |
| Removed or deprecated facility | Distinguish removal from deprecation and recommendation. Check authoritative package docs; supported older APIs need not all be replaced. |
| Toolchain or runtime change | Test relevant behavior even if no source rewrite is needed. Check platform support, build tags, runtime settings and CI images as part of the authorized upgrade. |

The version migrations reference lists the known non-mechanical replacements. A gopls rename cannot migrate an external API's signature or semantics by itself.

Apply a selected fixer (the tooling reference covers availability) to a bounded, recoverable change and inspect every resulting category. Formatting changes and dependency tidy changes should remain attributable to the migration. Run tidy only when module changes are needed, review its diff, and preserve the supported version policy.

## Compatibility evidence

Run build, vet and tests with the intended target and the oldest retained supported toolchain, across affected modules and relevant tagged/platform variants. Pin the toolchain for each run (`GOTOOLCHAIN=local` with that toolchain's `go`, or `GOTOOLCHAIN=go1.N.M`) and record `go version` beside each result, because automatic switching silently turns a minimum-version test into a newer-version test. An unavailable old toolchain is an unverified claim, not a pass.

For a version bump, inspect runtime compatibility settings in module/workspace configuration, source `//go:debug` directives and deployment environments. Isolate intentional behavioral migrations from the version-only change. Report declined, deferred, unsupported and applied candidates separately.
