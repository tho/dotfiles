# Running linters and interpreting findings

Run with the repository's intended Go version, linter version, working directory, config, build tags, and module/workspace scope. The module root is a useful starting point; `./...` at a workspace root without a module may fail or omit modules. Identify the intended modules and use their package patterns. A list of changed Go files is not a substitute for a package: it can omit declarations, tests, or build constraints needed by analysis.

For golangci-lint, inspect configuration discovery (for example `config path` where supported), then run the requested scope with package paths such as `./...` or `./internal/parser/...`. Isolate one analyzer with `--enable-only <linter>`, use `--verbose` for loading and timing detail, and apply formatting through `golangci-lint fmt`, checking each flag against the installed command help. `go vet ./...` and `staticcheck ./...` are standalone alternatives for those analyses, not substitutes for every configured golangci-lint check. Running a single linter isolates a diagnostic; finish with the relevant configured checks when claiming the requested scope is clean.

## Reading the result

For each actionable finding, inspect enough code around the reported position to establish the cause. Explain the behavior or policy involved and whether the right response is a fix, a documented exception, or more investigation.

Prioritize demonstrated correctness, security, and resource-lifetime defects. A resource leak deserves a fix; an analyzer unable to follow ownership transfer may deserve a narrow exception after that transfer is verified. An unused authentication helper might indicate missing wiring rather than code to delete. Complexity and naming warnings report policy checks, not proof that a rewrite improves the program.

Separate analysis failures (package loading, type errors, unsupported Go versions, missing dependencies, timeout) from lint findings. Capture stderr and exit status along with output, and classify the run by exit status first: golangci-lint uses one code for issues found (set by `--issues-exit-code`) and others for failures and timeouts, as documented for the installed version. An empty diagnostic list after failed analysis proves nothing. A missing linter calls for checking the installed version and available checks before proposing a compatible replacement or upgrade.

For a timeout or resource limit, use verbose timing and the actual configured timeout to identify the constraint. Increase a too-small timeout when warranted. Lower concurrency for memory pressure, not as a universal speedup. Avoid a hardcoded claim about timeout defaults across versions.

## Incremental adoption

For a backlog, retain a full diagnostic inventory and choose a deliberate comparison revision for new-issue reporting, using the `new-from-rev` or `new-from-merge-base` option. Ensure the base exists locally and matches the team's change boundary. `HEAD~1` covers only the last commit and can miss earlier changes in a branch. New-issue filtering limits reported findings; it does not prove old code is clean or necessarily reduce analysis work.

Track backlog cleanup separately, and use periodic unfiltered runs to measure what remains. Avoid mass `nolint` insertion or disabling checks as a substitute for an adoption policy.
