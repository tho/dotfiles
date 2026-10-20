---
name: golang-testing
description: 'Writes and reviews Go tests that verify observable behavior. Use when adding or reviewing _test.go files with unit, table-driven, integration, HTTP, fuzz, golden-file or regression tests; auditing coverage and test isolation; or using testify assertions, mocks and suites. Not for diagnosing unexplained failures or flakes (golang-debugging), or writing benchmarks and analyzing performance (golang-performance-engineering).'
---

# Go Testing

Give Go developers tests that protect observable contracts and explain failures, with evidence of what ran and what remains unverified.

## Testing default

Standard-library assertions are fine for trivial tests, such as a single uncomplicated check. For nontrivial new or substantially rewritten tests, use testify's `assert` and `require` as the default unless the user or project explicitly specifies otherwise. Judge complexity across the behavior being tested: splitting a scenario into short subtests does not make setup, state transitions, structured comparisons, or error paths trivial. Keep Go's `testing` package as the foundation; this default does not require mocks or suites, or migrating unrelated existing tests.

## Test quality

- Assert behavior promised by the contract, including boundaries and error paths. Prefer the external test package for public APIs; use internal access when the behavior under test actually requires it. Coverage shows execution, not assertion quality.
- Give table cases descriptive subtest names. Prefer source-derived test filenames and matching function order for navigation; follow an established repository layout where it differs.
- Isolate mutable fixtures and register cleanup as resources are acquired. Parallelize only independent tests. Synchronize on observable completion instead of guessing with sleeps.
- Respect the module's Go version (`go list -m -f '{{.GoVersion}}'`), selected testify version (`go list -m github.com/stretchr/testify`), and explicit dependency constraints. Confirm an unfamiliar API exists in those versions with `go doc <pkg>.<Symbol>` before emitting it.

## Focused references

Read only the reference relevant to the task.

| Concern | Reference |
| --- | --- |
| Assertion choice, mocks, argument matching, suite lifecycle | [Testify](references/testify.md) |
| HTTP tests, integration boundaries, fixture ownership and cleanup | [Integration](references/integration.md) |
| Parallel isolation, worker assertions, timing, race and leak checks | [Concurrency](references/concurrency.md) |
| Coverage gaps, fuzz properties, golden files and executable examples | [Coverage and fuzzing](references/coverage-and-fuzzing.md) |

## Verification and handoff

For implementation, run the affected tests and checks appropriate to the changed behavior. For a regression test, show it is a real oracle when feasible: it fails against the pre-fix production code (revert only that change, without discarding uncommitted work) and passes with the fix; report both runs. Report commands, results, and anything unverified, including unavailable external services.

For reviews, identify the location, the faulty behavior a test would miss, and a concrete improvement. Separate style preferences from defects. Do not weaken assertions or change production behavior just to make a test pass.
