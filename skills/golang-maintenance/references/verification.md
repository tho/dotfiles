# Evidence for maintenance changes

Inventory the current diff and establish a recoverable baseline for affected files and packages before transforming them. Preserve unrelated edits and distinguish existing failures from regressions. Verification follows the behavior and supported environment, not the number of changed lines.

## Choose a safety net

- For a small semantic rename with exercised callers, existing tests plus build/vet checks may be enough.
- For uncovered logic, add characterization tests before changing structure, including awkward error and edge cases. Pin observable results, errors, side-effect ordering and resource lifetime. Confirm the tests execute the affected code.
- For exported changes, include a representative external consumer and API compatibility checks. Workspace reference searches miss downstream modules.
- For reflection or serialization, test wire names, template selectors, configuration keys and type identity. Compilation cannot see string-based contracts.

Turn each compatibility promise into an assertion that would fail if that promise broke. A nil-input test must write to the returned clone when writability is promised, not merely call the function without panicking. Likewise, a field rename needs an assertion on the serialized key and rendered template output; a package move needs a consumer that still compiles using the old exported name. State these assertions explicitly even in an advisory plan. Before claiming preservation, confirm the relevant tests ran; adding a case with no discriminating assertion is not evidence.

Go coverage measures executed statements, not branches, interleavings or inputs, so even 100% proves little; use it to find untested paths, never as permission to proceed. Scope `-coverpkg` and the package list to the changed packages, because a global average can hide the only function being changed, and check uncovered error and boundary paths in the changed lines directly. The profile is an output artifact, not a tracked source change.

## Checks

Run build, vet and tests in each affected module root, using focused package tests while iterating and the broader affected consumer suite before handoff. A root invocation does not cover nested modules; enumerate them with `go list -m -f '{{.Dir}}'` in a workspace, otherwise with the `go.mod` files outside `vendor/` and `testdata/`. Exercise supported build tags and platforms; distinguish cross-compilation from executed tests. Regenerate generated sources through their owning generator where available.

Use the race detector when synchronization, goroutine ownership or shared data changes. For hot paths, keep repeated before/after benchmarks (same toolchain, environment and workload, compared with benchstat) as their own evidence, distinct from the behavior tests.

## Review obligations

Check nil versus empty values, aliasing, allocation/identity where observable, side effects, defer timing, panics, error matching, output formats and exported compatibility.

For refactoring, confirm that neither the version floor nor a dependency requirement changed incidentally. When a step fails, identify its cause or revert only that step; repairing forward with unrelated changes erases the causal evidence.
