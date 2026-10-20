# Collection ownership

Choose whether an API borrows, transfers, or copies data. Defensive copying follows that contract; exported functions may intentionally return a documented mutable view.

## Aliasing and isolation

Assigning or slicing a slice shares elements; append can reuse spare capacity and overwrite another slice's elements.

```go
// Safe to append without overwriting the caller's spare capacity.
extended := append(input[:len(input):len(input)], extra)

// Independent existing elements, whether or not anything is appended.
independent := slices.Clone(input)
```

A full slice expression limits capacity; it does not copy existing elements. Appending at least one element beyond that capacity allocates another array. Appending zero elements does not establish independence.

slices.Clone and maps.Clone (Go 1.21+) copy one level. Pointer elements, nested slices, maps, and referenced objects remain shared. Copy the mutable layers that the API promises to isolate, including both ingress and egress where callers retain input references. Preserve intended nil-versus-empty semantics; maps.Clone(nil) remains nil and needs initialization before writes.

Copy a retained small subslice when retaining its entire large backing array would violate the intended memory lifetime.

## Iteration and mutation

The effective Go language version determines loop variable semantics. With Go 1.22 or later, variables declared by a loop using `:=` are distinct per iteration. Variables assigned using `=` remain shared. Earlier language versions reuse declared loop variables too.

Even with per-iteration variables, the address of a range value points to a copy, not the slice element. Use the element's index when mutations must affect the original slice.

Deleting map entries during range is allowed; entries inserted during range may or may not be visited.

## Equality and concurrent access

slices.Equal and maps.Equal treat nil and empty as equal; check nil separately if the contract distinguishes them. Use custom comparisons for nested structures or floats.

Copying a map is a read; it does not make an unsynchronized snapshot safe against concurrent writes.
