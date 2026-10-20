# Build and environment failures

Preserve the first relevant compiler, linker, or startup error and the exact failing command. Later errors can be consequences. Narrow to the affected package while retaining the original build tags, target, and CGO settings.

## Compare the effective build

Inspect `go version`, the module's `go` and `toolchain` directives, active workspace, selected dependency versions, replacements, and vendor mode. Targeted `go env GOMOD GOWORK GOVERSION GOOS GOARCH CGO_ENABLED` output helps compare local and CI runs. Inspect relevant `GOFLAGS` and `GOTOOLCHAIN` settings without dumping unrelated environment values or credentials.

For undefined symbols or missing files, check package/import identity, filename OS/architecture suffixes, build constraints, generated sources, and the actual selected files. Run `GOOS=<os> GOARCH=<arch> go list -e -tags=<tags> -f '{{.GoFiles}} {{.IgnoredGoFiles}} {{.Error}}' ./path/to/pkg` under each build context, local and CI, and diff the output.

For CGO and linking, compare compiler availability and target, system headers and libraries, search paths, and architecture. Follow the actual diagnostic rather than enabling CGO or injecting machine-specific flags blindly.

## Module and dependency evidence

Use `go list -m all`, `go mod graph`, or `go mod why -m <module>` for the specific selection question, respecting network availability and private-module settings. `go mod verify` checks downloaded module content against its recorded hashes; it does not prove runtime compatibility or that every required dependency is available.

Do not clear the module cache, run `go mod tidy`, or lower the declared Go version as a generic repair. Those changes can erase evidence or change dependency selection without explaining the failure. If a dependency or workspace mismatch is confirmed, make a targeted correction and rerun the original command under the intended release conditions.

## Runtime environment and external boundaries

For startup or external-call failures, an unchanged application revision does not rule out code paths triggered by new input or configuration. Probe with a safe, minimal request that matches the application's destination and protocol; avoid replaying writes, payments, or queue consumption simply to test connectivity. Record sanitized differences and the experiment that establishes their relevance.
