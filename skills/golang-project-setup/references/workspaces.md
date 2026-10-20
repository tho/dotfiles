# Modules and workspaces

Split modules only for independent release or consumption requirements, accounting for the added tagging, dependency, and CI work.

Initialize each member with its intended import identity, then run `go work init ./lib ./service` from their common parent. For an existing workspace, preserve its entries and add modules with `go work use ./lib ./service`. Remove an entry with `go work edit -dropuse=./lib`. `go work use -rm` is not a valid removal command. Inspect changes to go.work and go.work.sum. Use a workspace Go version compatible with every member module, and retain the project's toolchain policy.

Workspace use entries resolve local modules without permanent local-path replace directives in distributable go.mod files. They do not make missing require directives or unpublished versions valid for downstream consumers. A workspace replace directive is a local development override, not a release mechanism. `go work sync` can update member dependency versions and go.mod files; run it only when that synchronization is intended and review the diffs.

## Verify both development and release boundaries

Run build and test commands in each member directory with the intended workspace active. `go env GOWORK` identifies the active file, including one inherited from a parent directory. A workspace-only root's `go test ./...` does not enumerate member modules, so list them with `go work edit -json` (`Use[].DiskPath`) and address each one.

For every independently consumable member, also run from its module directory:

```sh
GOWORK=off go build ./...
GOWORK=off go test ./...
```

These checks still honor replace directives in go.mod, so run `go mod edit -json` in each member and flag `Replace` entries whose `New` has a `Path` but no `Version`: consumers will not have those local paths. Verify require versions are published and fetchable without the workspace; a synthetic v0.0.0 requirement satisfied locally is not release readiness. If a new library must be published first, report that dependency and the failing standalone check rather than hiding it with a replacement. Do not publish as an implicit setup step.

Decide whether go.work is shared repository configuration or developer-local configuration from the team's workflow. Commit intentional shared workspace state, including applicable sums; ignore personal workspace state consistently. CI for released modules should include standalone checks so a checked-in workspace cannot conceal missing dependencies.
