# Code clarity details

Improve the reader's understanding while preserving observable behavior and repository conventions.

## Expressions and declarations

Break long lines at semantic boundaries. Around 120 columns or four arguments is a cue to inspect a call, not a reason to fight `gofmt` or an explicit user constraint. For genuinely multiline calls or signatures, one argument or parameter per line often makes differences easier to scan. A long signature may instead need a coherent parameter object; avoid a miscellaneous options bag.

Use `var count int` or `var buf bytes.Buffer` when a useful zero value expresses intent. Use `name := "default"` for an initial nonzero value. Prefer keyed struct literals so readers can identify fields and avoid dependence on positional layout.

Nil slices are useful zero values and support append; initialize an empty slice when an API promises JSON `[]` rather than `null`. Maps must be initialized before assignment, but nil maps can be read safely. Eager allocation such as `m := map[K]V{}` removes the nil state that `if m == nil` lazy-initialization checks rely on, so the initializer they guard never runs. Preallocate from a known expected size, not an arbitrary large capacity. Preserve existing nil/empty behavior unless changing the contract is authorized.

## Control flow

Handle errors and edge cases early, leaving the happy path at minimal indentation. Drop redundant `else` after `return`, `break`, or `continue`. For simple configuration, a default followed by overrides can be clearer; preserve branch priority when conditions overlap.

Extract dense conditions into meaningful names only when evaluation remains safe and equivalent. Three operands is a readability cue, not a quota. Retain nil guards, expensive checks, and side-effecting calls behind their original short-circuit conditions:

```go
if user != nil && (user.IsAdmin || expensivePermissionCheck(user)) {
    allow()
}
```

Computing `isAdmin := user.IsAdmin` first would remove nil protection. Computing permission eagerly would change cost and possibly behavior. If extraction is needed, a small predicate function can preserve the complete condition.

Scope temporary variables to their use, as in `if err := validate(input); err != nil`. Prefer `range n` for simple counting when the project's Go version supports it (Go 1.22+). Retain index loops when their index progression is part of the algorithm.

## Functions and values

Around four parameters is a prompt to consider grouping, not permission to redesign a stable API. Put `context.Context` first when present, then inputs and output destinations as the API requires. Let an existing interface's signature take precedence. Functional options can suit growing optional configuration; an options struct may be enough.

Name results when they clarify meaning; write explicit return expressions except in very short functions where bare returns remain obvious. Keep return semantics intact when deferred functions modify named results. Keep cleanup in `defer` even when a function has one return path, because deferred calls also run during panic unwinding and a return-path call does not.

Pass small read-only values such as strings, numbers and `time.Time` by value. Use pointers for mutation or meaningful absence; assess copy cost for large structs. The common roughly 128-byte threshold is only a heuristic: allocation, escape behavior and access patterns can outweigh copying. Types with locks or other no-copy semantics require separate care. Benchmark performance claims rather than inferring a universal pointer advantage.

## Organization and small operations

Group related types, constructors and methods; a substantial primary type often deserves its own file. A useful file order is package documentation, imports, constants, types, constructors, methods and helpers, adjusted to keep related declarations together. Restrict blank imports to deliberate side-effect registration, preferably at application/test boundaries. Avoid dot imports in library code because they obscure name ownership.

Keep helpers unexported until callers need a public contract. Use `strconv` for simple conversions, `fmt.Sprintf` for richer formatting, `%q` to expose string boundaries in errors, `+` for small concatenations and `strings.Builder` for incremental construction where suitable.

Use concrete types when known and type parameters when the relationship between types matters; `any` remains appropriate for genuinely heterogeneous values. Make conversions explicit and check bounds when narrowing. Prefer standard `slices` and `maps` facilities where the Go version permits. Introduce abstraction or reflection for a concrete need, and dependencies only when their benefit justifies their cost.
