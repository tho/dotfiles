# Module changes

A module change is reviewable when the intended dependency and the resulting build list agree, consumers can resolve it, and incidental version changes are explained.

## Selection and scope

Inspect the module's go and toolchain directives, workspace context, existing replacements, and relevant imports before choosing a version. A dependency whose go directive is newer than yours raises your module's minimum when added; pick a release compatible with the project's floor. List existing replacements compactly with `go list -m -f '{{if .Replace}}{{.Path}} => {{.Replace.Path}} {{.Replace.Version}}{{end}}' all`.

MVS selects the highest minimum required version for each module path in the applicable graph, not the newest available release. A requirement is not an upper bound. Confirm the selected version with `go list -m MODULE`; adding a requirement cannot pin below another requirement's minimum. In pinning or downgrade advice, explain that requesting a lower version can downgrade other modules too: the change applies to a requirement graph, not an isolated pin.

## Add, remove and change major versions

Use `go get MODULE@VERSION` for an agreed version. Let Go derive a pseudo-version from a commit instead of constructing one. Remove or replace imports before tidying a removed dependency. `go get MODULE@none` can also remove or downgrade modules that require it, so inspect the complete diff.

Run `go mod tidy` in each affected module and inspect both go.mod and go.sum. Tidying includes test and build-tag dependencies; do not delete a requirement merely because the current binary does not import it. `// indirect` does not mean test-only or unused.

For module-aware v2+ releases, update the module path and affected imports to the `/vN` path. Account for gopkg.in's dotted version paths and legacy `+incompatible` versions rather than mechanically appending `/vN`. Major upgrades include call-site migrations and behavioral checks; successful resolution alone is insufficient.

## Conflicts and overrides

Trace the requirement with `go mod graph` and the import reason with `go mod why -m`. Prefer selecting a compatible published version or upgrading the parent dependency over inventing an override.

| Directive | Meaning and limit |
| --- | --- |
| replace | Substitutes module contents. Does not itself add a requirement or establish API compatibility. A local filesystem replacement will not exist on another machine unless provisioned. |
| exclude | Main-module policy excluding a dependency version. Inspect the resulting selection; it is not a general upper-version constraint. |
| retract | Author declaration that a published version should not normally be selected. Publish a version containing the retraction; the retracted version remains explicitly downloadable. |

Dependency modules' replace and exclude directives do not propagate to consumers. Workspace replacements affect local workspace builds, so check the published-library case outside the workspace. A fork used by a library needs a consumer-resolvable solution, such as an upstream fix or a distinct module/import path; a replace directive in the library alone does not deliver it.

For a temporary override, record its reason, compatibility evidence and removal condition. Verify the resolved versions and affected builds/tests after the override, including an external consumer when publishing a library.
