# Testify

Testify assertions complement `testing`; mocks and suites are optional tools, not the default architecture.

## Assertions

Use `require` for prerequisites and `assert` for independent observations. A failed `assert.NoError` does not guard the next pointer dereference. Create `is := assert.New(t)` and `must := require.New(t)` inside each subtest, or pass that subtest's `t` to package-level functions; a parent-bound helper attributes failures to the wrong test.

| Contract | Assertion |
| --- | --- |
| Value equality | `Equal(expected, actual)`; it compares pointed-to values too |
| Pointer identity | `Same(expected, actual)` |
| Wrapped sentinel or typed error | `ErrorIs(err, sentinel)` or `ErrorAs(err, &target)` |
| Error message is the contract | `EqualError` or `ErrorContains`, according to the promised precision |
| Unordered collection with duplicate counts | `ElementsMatch(expected, actual)` |
| Floating point tolerance | `InDelta` or `InEpsilon`, with domain-derived tolerances |
| JSON semantics | `JSONEq(expected, actual)` rather than whitespace-sensitive strings |

Keep expected values first in equality assertions. Use `EqualValues` only when conversion is intentionally part of the contract. Assert nil versus empty separately when the API distinguishes them.

Fatal assertions call `FailNow`, so use them only in the test goroutine. For asynchronous polling, use bounded `Eventually` or `EventuallyWithT` where available in the selected testify version. In a collector callback, assert against its `*assert.CollectT`; guard dependent checks with a conditional return after a failed assertion. Do not dereference an unsuccessful result or capture the outer test's `require` helper there. Polling is not synchronization for shared unsafely accessed memory.

## Mocks

Use a fake when state or a small implementation describes the dependency better; use `testify/mock` when interactions are contractual. Mock a consumed interface and keep assertions focused on observable calls, not incidental call order.

- Embed `mock.Mock`, implement methods using `Called`, and return values with the declared types. Check a nil return slot before type-asserting a pointer.
- Register `AssertExpectations(t)` with `t.Cleanup` so early fatal assertions cannot skip verification. Join asynchronous callers before verification runs.
- Use `.Once()` or `.Times(n)` for required counts. `.Maybe()` makes a call optional and can conceal a missing required interaction.
- Match meaningful arguments exactly or with typed `MatchedBy` predicates. Reserve `Anything` for arguments irrelevant to the tested contract. `AnythingOfType` uses a type-name string; do not guess its package-qualified form.
- Bound successive return expectations explicitly, such as two `.Once()` calls for a retry. Assert order only if it is promised behavior; unordered expectation verification does not prove order.
- Mock arguments that are mutable pointers can change after the call. Capture a copy of the relevant value in a `.Run` callback when call-time contents matter, with synchronization if accessed across goroutines.

## Suites

Choose a suite only when its lifecycle improves repeated setup. Launch it from a normal Go test with `suite.Run(t, new(MySuite))`; suite methods alone are not discovered by `go test`.

`SetupSuite` and `TearDownSuite` bracket the suite; `SetupTest` and `TearDownTest` bracket each test. Reset mocks and mutable fixtures per test. Suite assertions such as `s.Equal` continue after failure; `s.Require()` is the fatal variant. For suite subtests use `s.Run` so the suite tracks the current test.

Testify suites do not support parallel tests. Keep suite tests and suite subtests sequential; use ordinary `testing.T` subtests with independent state when parallelism is required.

`testifylint` can catch mechanical assertion mistakes; use the repository's lint configuration instead of assuming it is installed or that lint replaces behavioral review.
