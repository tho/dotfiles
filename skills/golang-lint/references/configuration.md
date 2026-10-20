# Linter configuration

Work from the repository's configuration, task runner, pinned linter version, and Go version. Inspect `golangci-lint version`, `golangci-lint linters`, and command help before relying on a flag or linter name. If the binary is absent, report that limitation and use the project's documented installation method with a compatible pinned release; an unqualified `@latest` can change both schema and analysis behavior.

## Choosing checks

For a new configuration, start with a small explicit set of broadly useful checks such as govet, staticcheck, unused, ineffassign, and errcheck. Add checks for the project's actual risks: resource ownership, SQL rows, logging calls, or security-sensitive operations. Inspect individual diagnostics rather than treating a linter's category as proof of severity. Staticcheck and revive, for example, cover more than one kind of concern.

Choose style, complexity, and naming checks to enforce an agreed repository policy. Their thresholds are policy decisions, not universal limits or instructions to split functions mechanically. For judgment about names and readability, invoke the `golang-conventions` skill. Avoid adding overlapping checks or broad test/example exclusions just to lower the count.

## golangci-lint v2

The v2 schema separates these concerns:

| Purpose | Configuration |
| --- | --- |
| Schema version | `version: "2"` |
| Explicit baseline | `linters.default: none`, then `linters.enable` |
| Per-linter options | `linters.settings` |
| Linter exclusions | `linters.exclusions` |
| Formatter choice and options | `formatters.enable`, `formatters.settings` |
| Formatter exclusions | `formatters.exclusions` |
| Analysis timeout, tests, build tags | `run` |
| Reporting limits and new-issue filtering | `issues` |

Enabling linters without choosing a baseline can also retain the tool's default linters. Keep this distinction explicit when a user requests an exact set. Verify configuration with `golangci-lint config verify` using the same binary and config that will run analysis; schema validity alone does not prove packages were analyzed.

Configure gofmt, gofumpt, goimports, or other formatters under `formatters`, not `linters`. Use `golangci-lint fmt` to apply formatting; whether `run` also reports formatting diagnostics depends on the version. Line length is a policy choice (`golines` formatter or `lll` linter). Adopt stricter formatting or a line limit only when requested or already established.

## Migration and exclusions

For v1 configuration, use the target v2 binary's `migrate` command after preserving the original. Inspect the diff for renamed/removed checks, settings, default sets, and exclusion behavior. Verify and run the migrated configuration; do not resolve incompatibility by silently dropping checks. A supported older installation may instead need its existing v1 config preserved.

Use exclusion rules scoped to the relevant path, linter, and diagnostic when a recurring exception is justified. Linter exclusions filter reports and need not prevent package loading or analysis, so they are not a general performance solution. Inspect generated-file and preset exclusions before promising coverage of generated code or tests.
