# Nil and initialization

Define which absent values are valid for the API. Distinguish a usable zero value from a value that requires construction, and preserve that distinction on failure paths.

## Interfaces and assertions

An interface equals nil only when both its dynamic type and value are absent. A typed nil pointer assigned to error, a handler, or any other interface makes a non-nil interface. Return a literal `nil` on the success or absent branch, never a typed pointer variable that may be nil.

Neither errors.Is(err, nil) nor comparing the interface directly to nil removes a typed nil. Fix the return boundary. For an existing interface that may intentionally hold a typed nil, validate according to the supported concrete types.

In reflection code on Go 1.25+, reflect.TypeAssert[T] supports comma-ok extraction; inspect validity and accessibility when reflect.Values can be invalid or refer to unexported fields.

For a comparable type parameter, comparison with its zero value is valid and answers whether it is zero, not specifically nil. An unconstrained type parameter cannot be compared to nil; constrain the type or define the intended zero-value semantics.

## Nil receivers and callbacks

Accept a documented nil-safe receiver rather than rejecting it merely because it is nil. Guard optional callbacks, or supply defaults that callers cannot bypass by skipping construction. Make required dependencies fail clearly when absent instead of silently dropping work.

## Construction and zero values

Lazy initialization can support useful zero values, such as allocating a map on first write, but unsynchronized initialization is only appropriate when access is not concurrent.

Exporting a struct with a constructor does not prevent callers from declaring its zero value. Either make the zero value useful, detect invalid state, or document and enforce construction at the appropriate API boundary.

sync.Once runs its function once, including when that function returns a failure or panics. If initialization can fail, retain and return the error; do not discard it and publish a nil resource. If retries are required, once-only initialization does not meet that contract.
