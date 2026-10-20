---
name: golang-correctness
description: 'Guides Go correctness across error handling and defensive coding. Use when writing or reviewing Go error contracts, %w wrapping, errors.Is/As/Join, panic vs error, typed-nil bugs, nil maps and zero values, slice/map aliasing, numeric overflow, NaN comparisons, or defer/Close cleanup mistakes. Not for concurrency design, security audits, production incident diagnosis, or logging infrastructure setup.'
---

# Go Correctness

Help Go developers preserve observable behavior on failure and at data boundaries. The outcome is code whose error contracts, ownership, numeric limits, and resource lifetimes are explicit enough for callers and reviewers to rely on.

Gate version-specific APIs on the module's language version (`go list -m -f '{{.GoVersion}}'`); a file's `//go:build go1.N` line overrides it for that file, including loop variable semantics. Preserve existing public API contracts.

## Correctness bar

- Give each failure an owner: recover meaningfully or propagate useful context to the caller. Preserve inspectable causes when they belong to the API contract; log terminal failures once at the responsible boundary.
- Treat nil, empty, absent, and invalid as distinct states wherever the contract distinguishes them. A typed nil inside an interface is not a nil interface.
- Establish who may mutate shared slices, maps, and nested values. Copy when independence is promised; capacity limits and shallow copies do not provide deep isolation.
- Check numeric ranges before narrowing or arithmetic that can overflow. Choose floating point comparisons and zero-divisor behavior from domain requirements.
- Release owned resources on every relevant exit, at the intended lifetime boundary. Preserve meaningful cleanup errors alongside the primary failure.

## Focused references

Read only the references relevant to the code being changed or reviewed. Paths are relative to this skill's directory.

| Concern | Reference |
| --- | --- |
| Error values, chains, joining, panic/recover, and logging ownership | [Errors](references/errors.md) |
| Typed nils, assertions, callbacks, receivers, and initialization | [Nil and initialization](references/nil-and-initialization.md) |
| Aliasing, defensive copies, iteration, and collection contracts | [Collections](references/collections.md) |
| Numeric bounds, floating point behavior, resource cleanup and cleanup errors | [Numbers and resources](references/numbers-and-resources.md) |

## Evidence and handoff

For implementation, test the affected failure paths and boundary values, and run existing checks such as `go vet ./...` and `go test -race` where shared maps or slices are touched. Report what ran and what stayed unverified.

For review, tie each finding to a file location, a reachable failure condition, its consequence, and a concrete correction. Distinguish a demonstrated defect from a missing contract or a style preference.
