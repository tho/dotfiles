# Justified suppressions

A suppression records why a specific diagnostic is acceptable in its actual context. Check whether the finding is real before choosing an exception. “Legacy code”, “lint complains”, or “fire-and-forget” alone does not establish that an ignored error, unchecked assertion, or security finding is harmless. For correctness, security, and resource checks, identify the verified invariant or ownership path that makes the exception safe.

## Directive scope

Use the narrowest supported placement, usually on the affected line or immediately above it:

```go
value := input.(Record) //nolint:forcetypeassert // The enclosing type switch established that input is a Record.
```

Use actual analyzer names from the finding. A single directive can name several: `//nolint:errcheck,gosec // reason covering both findings`. Keep `//nolint` contiguous, specify the linters, and include a concrete explanation. A directive on a function can cover its body; a file-wide directive has wider scope still. Prefer local placement unless the exception genuinely covers the larger region.

For a long table-driven test or intentional duplication, explain the specific tradeoff after applying the repository's policy. For a temporary compatibility exception, name the blocker and the removal condition.

## Enforcing and auditing exceptions

With golangci-lint v2, enable `nolintlint` with `require-specific: true`, `require-explanation: true` and `allow-unused: false` under `linters.settings`, as in the [baseline](../assets/.golangci.yml), merged into the existing settings rather than replacing the configured checks. Enabling `nolintlint` alone does not imply both explanation and specificity requirements are enabled. It can check directive syntax and usefulness, but cannot establish the truth of a justification.

Run the targeted analyzer and the configured hygiene checks after editing. Confirm the directive applies to the intended finding; remove stale or unnecessary directives rather than weakening the unused-directive check. Check configuration exclusions too: a hidden finding can make a directive appear unnecessary.

The `//nolint` convention belongs to golangci-lint and does not universally suppress standalone tools. Standalone Staticcheck uses its own `//lint:ignore CHECK reason` convention. `go vet` has no general `//nolint` mechanism. Verify the actual runner before recommending a suppression.
