# Collection and generic API design

Choose representation from required operations, ordering, identity, and ownership. Performance claims need representative measurement; runtime map layouts and slice growth factors are not API guarantees.

## Representation

| Need | Starting point and constraint |
| --- | --- |
| Repeated priority extraction | container/heap; define ordering, ties, and how priority updates maintain the heap |
| Constant-time removal at an already-known position | container/list with element handles; finding an element still takes a scan without another index |
| Bounded FIFO or rolling window | Slice-backed circular buffer is often sufficient; container/ring is a circular linked list, not a contiguous queue with built-in overflow policy |

Define whether text operations use bytes, code points, or user-perceived characters.

## Generics and constraints

Use type parameters for operations that share behavior across element types. Use interfaces for varying behavior and a concrete type when there is no useful generalization. The number of current instantiations is not a reliable prohibition on generics.

Choose the least restrictive constraint that permits the operations, or a supplied comparison function for domain ordering. Prefer available standard slices/maps operations over bespoke collections with no additional contract.

Interface values can be comparable at the type level yet panic during equality or map use if their dynamic values are not comparable. Go 1.20+ permits interface types to satisfy comparable constraints, but that does not guarantee all runtime contents are valid keys. Define the accepted key domain or validate a genuinely dynamic boundary.

## Ownership and iteration

State whether constructors and accessors retain, copy, or borrow slices, maps, and pointers. Assignment and slices.Clone/maps.Clone are shallow, so nested slices, maps and pointers still alias; deep isolation needs copying at every mutable boundary promised by the API.

Define nil versus empty results when callers or wire formats distinguish them. Map-backed collection writes need initialization; decide between a useful zero-value wrapper and an explicit constructor contract. Map iteration cannot promise stable ordering; return or iterate sorted keys if determinism is part of the API.

For large or lazy results, compare materialized slices, callbacks, iterators, or an existing streaming interface. Range-over-function iterators require Go 1.23+. Specify order, repeatability, errors, early termination, and resource lifetime. A yield returning false must stop production and release owned resources; terminal source errors must remain observable. Deferring work also defers errors, so laziness is not automatically a better caller contract.
