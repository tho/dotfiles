# Dependency reproducibility

Distinguish a repeatable module build list from reproducible build artifacts. The latter also depends on toolchain, platform, build flags, generated inputs, cgo/native dependencies and environment.

## Checksums and module inputs

Commit go.mod and the generated go.sum when present. go.sum authenticates downloaded module content; it is not a lock file, may include multiple versions, and is not a list of everything linked into a binary. A module without external dependencies may legitimately have no go.sum.

Explain download authentication separately from cache verification: downloads check existing go.sum entries and, for public modules by default, the checksum database. `go mod verify` checks cached module archives and extracted contents against hashes recorded at download time; it does not validate vendor contents, prove code safe, or substitute for download authentication. Investigate mismatches instead of deleting sums or disabling verification to make them disappear.

Use `go mod tidy` to reconcile intentional changes, then review its diff. `go build -mod=readonly ./...` helps catch required module-file updates, but is not an offline or fully immutable build.

## Workspaces and consumers

Check the active workspace with `go env GOWORK`. A workspace can mask a missing requirement, select a newer version, or use unpublished local code. `go work sync` can change member modules' requirements; review them all.

For each independently consumable module, verify with `GOWORK=off` and no unavailable local replacements. For a published library, use a separate consumer module or equivalent release check to establish that consumers can resolve it without the developer's workspace.

Choose whether to commit go.work and go.work.sum based on the repository's shared-workspace policy. Keep an intentionally shared workspace's inputs consistent. Do not impose a blanket ignore rule for go.work.sum or let a personal workspace silently control CI.

## Tools and vendoring

For Go 1.24+ projects, pin executable tools with `go get -tool TOOL_PACKAGE@VERSION` and invoke them with `go tool TOOL_NAME`. Tool directives identify packages; selected module requirements carry their versions. Inspect changes to the whole module graph. For older supported Go versions, retain a compatible tools.go pattern or a separate versioned tool installation policy. Do not raise the Go floor just to adopt tool directives.

For that older-Go tools.go pattern, put `//go:build tools` before a blank line and the package declaration, then blank-import the tool packages. The constraint keeps command imports out of ordinary builds. Pin with `go get TOOL_PACKAGE@VERSION`; `go install TOOL_PACKAGE` then uses the module's selected version. Alternatively, install a separately versioned tool with `go install TOOL_PACKAGE@VERSION`. Replace placeholders with compatible package/version choices; if those are unspecified, show the pattern without inventing pins. Verify using the actual supported Go toolchain: `GOTOOLCHAIN=local` prevents switching but does not select an older installed Go version.

Use explicit tool versions for repeatable setup, rather than unreviewed `@latest`.

When vendoring is the repository policy, regenerate with `go mod vendor` after dependency changes and review vendor/modules.txt and content. Use workspace vendoring only with a supporting toolchain and a deliberate workspace policy. Verify the actual vendor build mode.

## Private dependencies

Respect the existing GOPROXY, GOPRIVATE, GONOPROXY and GONOSUMDB configuration. Scope private module patterns narrowly so private paths are not sent to public proxy/checksum services and public verification remains enabled. Do not print credentials or solve authentication failures by broadly disabling verification. Private-module reproducibility also needs stable access and trusted immutable source or proxy storage.
