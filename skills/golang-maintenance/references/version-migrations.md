# Version migrations and semantic traps

Use the minimum supported Go version, not merely the installed compiler, to select an API. Verify exact signatures in official package documentation before editing. This is a decision aid, not a claim that every newer API belongs in every project.

## Release anchors

| Minimum | Candidate changes | Source |
| --- | --- | --- |
| 1.18 | any alias and type parameters | [Go 1.18](https://go.dev/doc/go1.18) |
| 1.21 | min/max, clear, slices/maps, slog, OnceFunc/OnceValue | [Go 1.21](https://go.dev/doc/go1.21) |
| 1.22 | Integer range, per-iteration declared loop variables, rand/v2, TypeFor, SQL Null[T], cmp.Or | [Go 1.22](https://go.dev/doc/go1.22) |
| 1.23 | Range over iterator functions, iterator collection helpers, new timer behavior | [Go 1.23](https://go.dev/doc/go1.23) |
| 1.24 | Generic aliases, os.Root, omitzero, SplitSeq, t.Context, b.Loop, AddCleanup, module tool directives | [Go 1.24](https://go.dev/doc/go1.24) |
| 1.25 | WaitGroup.Go and stable testing/synctest | [Go 1.25](https://go.dev/doc/go1.25) |
| 1.26 | errors.AsType, new(expression), analysis-based go fix | [Go 1.26](https://go.dev/doc/go1.26) |
| 1.27 | Generic methods, CutLast, uuid, JSON v2 APIs, httptest.NewTestServer | [Go 1.27](https://go.dev/doc/go1.27) |

For newer releases, consult the official [release history](https://go.dev/doc/devel/release). Confirm release status rather than treating a proposal, experimental API or development snapshot as a stable feature.

## Preserve the contract

| Replacement | Required check |
| --- | --- |
| interface{} to any | The alias requires Go 1.18; check shadowing of the predeclared identifier. This does not justify a generic API redesign. |
| Manual clone to slices.Clone/maps.Clone | Preserve nil versus non-nil empty values and shallow-copy aliasing. make plus copying a nil map yields a non-nil result, unlike maps.Clone(nil). |
| Manual min/max or defaulting to cmp.Or | Check floating NaN/signed-zero behavior, operand evaluation, and eager evaluation of fallback arguments. |
| Counting loop to integer range | A loop condition may reevaluate a changing bound; range evaluates its operand once. Preserve index type and post-loop uses. |
| Remove loop-variable copies | New semantics depend on the module/file language version and loop-declared variables. Assignment to a preexisting variable is still assignment. |
| rand to rand/v2 | Random streams, seeding, source interfaces and function names differ. Keep reproducible sequences if they are part of the contract; neither API is a substitute for cryptographic randomness. |
| Router replacement | Compare method handling, precedence, escaping, redirects and middleware before removing a routing dependency. |
| New timer semantics | A timer's collection eligibility is separate from stopping activity or coordinating a receiver. Do not remove Stop or drain logic without checking ownership and target behavior. |
| os.Root | Check the target version's actual methods, platform behavior and access policy. It is not a universal sandbox or substitute for authorization. |
| omitempty to omitzero | Serialized output changes; preserve consumer expectations or treat the change as an explicit wire migration. |
| Finalizers to AddCleanup | Cleanup must not keep its target reachable through captured state or arguments. It is not a deterministic resource-release mechanism. |
| t.Context / b.Loop / synctest | Test cleanup lifetime and benchmark setup/timing can change. Fake-time tests need compatible blocking operations; real network I/O is not fake-clock progress. |
| WaitGroup.Go | Check panic assumptions and existing Done calls; do not retain a deferred Done inside the function passed to Go. |
| errors.Is/As or errors.Join | Matching may broaden, formatting and multi-error traversal may differ. A supported API is not automatically behavior-equivalent. |
| slog or standard-library crypto replacements | Compare fields, levels, error surfaces, algorithms, protocols and signatures before replacing a dependency. |

## Go 1.27 distinctions

The [release notes](https://go.dev/doc/go1.27) distinguish implementation changes from API migrations:

- encoding/json uses v2 internally while preserving v1 marshaling/unmarshaling semantics. Explicit encoding/json/v2 use has stricter defaults, including duplicate-name and invalid-UTF-8 rejection. Diagnose the actual API and payload; a toolchain bump alone does not establish the cause of a decode regression.
- Removed GODEBUG settings in module entries or source directives accept their final default values and reject old values. Inspect each value instead of deleting every entry.
- Generic methods cannot implement interface methods. Preserve interface contracts during API restructuring.
- CutLast replacements must preserve the old missing-separator and leading-separator cases.
- Check uuid signatures and feature coverage before removing a dependency. Use the documented in-memory httptest server for synctest migrations.

For timer settings, [GODEBUG documentation](https://go.dev/doc/godebug) explains the compatibility mechanism; consult the target release and setting history. In particular, asynctimerchan=1 requests the older buffered behavior; zero denotes the newer behavior.
