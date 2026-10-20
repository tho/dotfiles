# Behavior-preserving refactoring

Keep the supported Go versions and observable contract fixed. A maintainer needs to see why the change preserves results, errors, side effects, wire formats, and public use, not only why it compiles.

## Inventory and order

For a multi-step change, record each transform, affected files/callers, external consumers, risk, prerequisite, and verification. A single local extraction needs only a short explanation. Map references and package imports before choosing the order; include generated code, build-tagged variants, tests, and external API users that workspace tools cannot enumerate.

Order overlapping file or symbol changes sequentially. A workspace-wide rename is a coordination barrier. A package move followed by an optimization gets separate steps with different evidence. Preserve a durable plan for a staged change, including any temporary aliases or adapters and their removal conditions. When PRs are requested, keep each independently reviewable and respect the repository's merge policy.

## Transform selection

| Change | Mechanics and preservation obligation |
| --- | --- |
| Rename | Prefer gopls symbol rename. Investigate conflicts instead of forcing textual replacement. Search old names in templates, reflection, configuration, tags, generated code, and external documentation. A Go field rename need not change its JSON or database name. |
| Extract function or variable | Preserve evaluation order, variable capture, pointer identity, named returns and deferred operations. Moving a defer into a helper changes when it runs. Review comments and build constraints after tool actions. |
| Inline | Check argument evaluation count and order, nil receiver behavior and stack-sensitive behavior. An available semantic action is preferable to duplicating expressions by hand. |
| Move a function or type | Map initialization order, unexported access, methods, import cycles, and external users. Use a forwarding function or compatible type alias where feasible; do not re-export a mutable variable as an independent copy. |
| Break an import cycle | A small interface owned by the consumer may remove a concrete dependency. Otherwise extract genuinely shared definitions into an acyclic leaf package. An internal package still needs an acyclic graph. |
| Change a signature | Prefer an additive adapter while callers migrate. Public removal or incompatible signature changes require an explicit compatibility decision. |
| Introduce a parameter object, interface, or generic | Avoid changing zero-value or nil behavior, method sets or comparable constraints accidentally. |

## Moving types incrementally

A type alias preserves identity between the new definition and the old exported spelling. A new defined type does not. For example, the old package can expose:

```go
// Deprecated: use model.Invoice instead.
type Invoice = model.Invoice
```

Move the definition and its methods together, retaining access to required unexported implementation. Confirm that the alias does not introduce a cycle and that the minimum Go version supports any generic aliases used. Reflection can still observe a changed defining package/name; test such contracts explicitly.

Keep the alias until the compatibility policy permits removal. No references in this checkout does not prove no external callers exist. For an approved breaking release, review semantic import versioning, including the module and import-path major suffix where applicable.

## Safety before structure

A minimal test seam is its own verified step. If characterization exposes wrong behavior, record a separate bug fix rather than changing the characterization expectations during extraction.

Completion means no unexplained behavior changes and a clear status for every temporary compatibility bridge.
