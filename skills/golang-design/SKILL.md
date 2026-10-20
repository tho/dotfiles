---
name: golang-design
description: 'Chooses Go package boundaries and public contracts. Use when explicitly asked to choose or evaluate package architecture (flat, clean, hexagonal, DDD), interface vs concrete types, constructor contracts (config structs, functional options), receivers and embedding, JSON wire contracts, generic collection and iterator APIs, or dependency injection (manual, Wire, dig, Fx, samber/do). Not for refactoring, package moves or compatibility bridges of an already chosen structure (`golang-maintenance`), goroutine or cancellation design (`golang-concurrency`), routine feature implementation, naming cleanup, performance tuning, SQL or deployment.'
---

# Go Design

Give a Go maintainer a design they can implement: package responsibilities, API contracts, dependency wiring, and the tradeoffs behind them. For a review, give concrete findings tied to the supplied code; for an explanation, answer without expanding it into a redesign.

Work from existing callers, import dependencies, invariants, supported Go versions, and team decisions. Prefer the simplest design that satisfies those constraints. Lines of code, service counts, and pattern names do not establish a need for layers, interfaces, generics, or a DI framework.

When a request also moves existing code, decide only the unresolved structure or contract here and leave migration mechanics to `golang-maintenance`.

## Design bar

- Put dependencies and their ownership in view: who constructs, mutates, starts, and closes each component. Distinguish application lifetime from request lifetime and unwind partially successful construction.
- Define abstractions around consumer behavior and actual variation. Concrete types and ordinary functions are valid dependencies; an interface or container needs a specific benefit.
- Make zero values, validation, optional values, errors, and collection ownership part of the API contract. Unexported fields and named constants alone cannot prevent every invalid state in Go.
- Preserve public source and wire compatibility unless a breaking change is requested. Changing receivers, embedding, return types, or exported fields can break callers even when local tests pass.

## Focused references

Read only the references needed for the requested design.

| Concern | Reference |
| --- | --- |
| Package boundaries, dependency direction, flat/clean/hexagonal/DDD choices | [Architecture](references/architecture.md) |
| Interfaces, constructors, embedding, receivers, zero values and serialization | [Types and APIs](references/types-and-apis.md) |
| Manual wiring, DI library tradeoffs, provider graphs and lifecycle ownership | [Dependency injection](references/dependency-injection.md) |
| Collection selection, generic constraints, copying and iteration contracts | [Collections](references/collections.md) |

## Evidence and delivery

Connect each recommendation to the requirement or coupling it addresses, including the simpler alternative and its tradeoff when a choice is contested. Keep unresolved requirements explicit instead of inventing an architecture preference.

For implementation, use the project's supported Go version (`go mod edit -json` shows the go directive) and pinned library APIs (`go list -m all`). Report checks actually run and any unavailable evidence. For review, distinguish demonstrated design problems from optional preferences; a named pattern or a long dependency chain alone is not a defect.
