# Dependency upgrades

Deliver the requested version change with evidence for compatibility and a bounded diff. Distinguish upgrading dependency versions from upgrading the project's supported Go version.

## Choose the update scope

List available updates compactly with `go list -m -u -f '{{if .Update}}{{.Path}} {{.Version}} -> {{.Update.Version}}{{end}}' all`, then read upstream release notes for the modules in scope. Prefer `go get MODULE@VERSION` for a targeted request. Do not turn one module update into a graph-wide update.

For routine bulk updates without a requested target, patch-only is a conservative starting point. Honor an explicit request for latest minor or major versions; do not silently substitute patch-only work. Patch/minor labels are compatibility claims, not proof, especially for v0 modules and behavior changes.

```sh
# Bulk patch updates, only when that scope is intended.
go get -u=patch ./...
go get -u=patch -t ./...
```

`-u` permits minor and patch upgrades within module paths. It does not automatically migrate imports to a new major path. `-t` includes dependencies needed by tests of the specified packages. Inspect selected versions to confirm the actual graph change rather than inferring it from the flag.

For a dependency requiring a newer toolchain, state the requirement and choose a compatible release or obtain a compatibility decision. Toolchain auto-selection can hide an unintended minimum-Go change. Treat upgrades to pinned tools as dependency changes too; they can affect the shared module graph.

## Compatibility evidence

Read migration guidance for changes affecting persistence, serialization, networking, authentication, cryptography or public APIs. Test the affected contracts, including old data or wire formats where relevant. A security fix can intentionally change behavior; it still needs review and verification. Urgency is not authorization to auto-merge.

After edits, tidy each affected module and review the full diff: direct and indirect requirements, checksums, imports, go/toolchain directives, and vendor or tool metadata. Explain unexpected changes or remove them if outside scope.

Run the project's build, test and static checks. In a multi-module repository a root `./...` need not cover every module; check each affected module and relevant consumers. Include the supported Go floor and important build tags/platforms when they bear on compatibility. Use the project's configured vulnerability scanner for dependency risk, reporting any missing scan or unsupported analysis configuration.

A failed check is not a verified update; identify whether it is caused by the upgrade, pre-existing, or unresolved.
