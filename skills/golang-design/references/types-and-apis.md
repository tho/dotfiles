# Types and API contracts

Design from caller needs and invariants. Keep signatures, zero values, ownership, and compatibility assessable without knowing implementation details.

## Interfaces and composition

Start with concrete types or functions. Introduce a consumer-owned interface for a real substitution boundary, including a test seam, without requiring two production implementations. Keep methods cohesive around what that consumer uses; a fixed method-count limit does not measure cohesion.

Concrete constructor results generally expose useful capabilities without prematurely freezing an abstraction. Returning an interface can be intentional for an opaque implementation, a factory selecting implementations, or an established public contract. Preserve that contract unless its change is in scope. Reuse standard interfaces when their semantics, not just signatures, fit.

Embedding promotes an API and may accidentally satisfy interfaces, including serialization interfaces. Prefer a named field when the dependency is internal. Promoted methods retain the embedded receiver; an outer method of the same name does not create virtual dispatch inside the embedded type. Audit promoted methods when an embedded dependency changes.

Use optional capability assertions to a small interface when absence is valid. Handle a failed assertion explicitly; a single-value assertion is appropriate only with an established invariant. Rather than a reflection-based check for every typed nil, define the constructor's accepted values and validate the relevant boundary.

## Constructors and configuration

| Form | Good fit |
| --- | --- |
| Direct value or small constructor | Useful zero value, few required inputs |
| Config struct | Related settings, readable defaults, whole-config validation |
| Functional options | Independent optional settings that evolve without growing positional parameters |
| Builder | A meaningful staged construction process that simpler forms cannot express clearly |

Keep required dependencies explicit. State default, unset, and explicit-zero semantics. For options, define ordering or duplicate handling, apply all options to private construction state, then validate cross-field invariants before exposing the result. Error-returning options are useful for per-option failures but do not replace final validation. Avoid acquiring resources inside options without a failure cleanup contract.

Avoid hidden service setup through mutable globals or init functions; explicit construction exposes dependencies and startup failures. Legitimate registration and immutable package initialization do not require a blanket ban on init.

## Zero values, receivers and copies

A useful zero value can remove a constructor, but lazy initialization must respect the promised concurrency behavior. If an external dependency is mandatory, document constructor requirements and the behavior of an uninitialized value instead of pretending the zero value works. Choose an enum's zero meaning deliberately; validate unknown numeric or wire values where the contract requires it.

Method sets and copy semantics decide receiver correctness, not consistency alone: T has its value methods, *T has both; automatic address-taking for an addressable call does not give T the pointer methods needed to satisfy an interface. Add a compile-time assertion where a particular implementation contract matters.

Copying a struct copies its fields, not the object graph. A channel field alone does not make copies invalid; both copies refer to the same channel. Locks, ownership relationships, self-pointers, or explicit library contracts may prohibit copying. A noCopy marker can help go vet detect misuse, but it does not enforce a runtime prohibition.

## Serialization and compatibility

Separate domain representation from a transport DTO when their invariants or evolution differ. Explicit field tags stabilize wire names; inspect the encoder and custom marshalers before claiming what is serialized. Avoid embedding a type with marshaling methods unless promoting that behavior is intended.

For encoding/json, omitempty never omits a struct value; omitzero requires Go 1.24+ and uses IsZero when defined. Neither alone distinguishes absent from explicit zero. Use a pointer when two states suffice, or a presence-aware representation/custom decoding when absent, null and zero must all differ.

Round-trip tests alone can miss a wire-name break; assert the actual external representation when compatibility matters.
