# Layout and initialization

Choose the smallest layout that supports the actual consumers.

| Need | Starting layout | Reason to expand |
| --- | --- | --- |
| Small standalone tool | Root main.go and go.mod | Extract packages when responsibilities or reuse justify them |
| Importable library | Root package files, tests, go.mod | Add public subpackages for distinct APIs; internal packages for private implementation |
| Server and worker released together | cmd/server/main.go, cmd/worker/main.go, internal packages, one go.mod | Separate executable entry points without independent module releases |
| Library plus executable | Root library package and cmd/tool/main.go | Keep package main separate from importable library code |
| Independently versioned components | A go.mod per release unit; optional go.work above them | Separate consumers, dependencies, or release policies justify module boundaries |

Keep startup and wiring near the entry point; extract logic when tests or reuse need it, not to fill a layer for each architectural term. Existing src or pkg directories are not language errors; move them only when the improvement warrants import-path churn.

## Import identity and initialization

Inspect existing go.mod, go.work, repository remotes, and toolchain constraints before initializing anything. Run `go version` to learn what is installed; it does not establish the project's minimum supported version. Choose the go directive from the support requirement and dependency constraints.

For a new module, run `go mod init <module-path>` from its intended root after resolving the path. Public modules need a fetchable import identity, often the repository path, or a configured vanity domain. For ordinary versioned modules at v2 or later, account for the `/v2` or later major-version suffix. Nested modules also need appropriate release tags for their repository subdirectory. Local-only module names are possible, but should not be presented as publication-ready identities.

Package names are Go identifiers, distinct from module paths; hyphens in a module path do not belong in a package clause.

## Supporting files

- Use package-local testdata for fixtures. Go source there can intentionally serve as fixture input. Cross-package helpers that must be imported need ordinary Go files, often in an internal testutil package; helpers in another package's test files are not importable.
- Add ignore patterns for actual outputs, not broad file extensions that hide fixtures. A standard-library-only module need not have go.sum. Preserve a deliberate vendoring policy.
- Keep tracked application config to non-secret defaults or examples. Runtime secrets come from the deployment's secret mechanism.
- Prefer existing build commands. Across several packages, `go build ./...` compiles and discards the results; produce a named binary with `go build -o <output> ./cmd/<name>`.

After adding real imports, run `go mod tidy` in the affected module and inspect the diff.
