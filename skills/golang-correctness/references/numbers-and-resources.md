# Numbers and resources

Use domain limits and ownership contracts to decide how invalid values and cleanup failures affect the result.

## Numeric boundaries

Integer conversions are explicit in Go, but narrowing or changing signedness can silently lose information. Check both lower and upper bounds before conversion; converting first destroys the evidence needed to reject the value.

Arithmetic can overflow before a cast. Converting an already-overflowed sum or product to a wider type does not repair it. Use checked arithmetic, a provably sufficient wider range, or arbitrary precision as the contract requires. Integer division truncates; convert operands before division when fractional results are intended, also considering overflow in earlier subtraction or multiplication.

For a zero divisor, choose rejection, an optional result, or a documented non-finite float result from the contract; do not invent zero as a fallback merely to avoid a panic. Account for minimum signed integer divided by -1 when exact mathematical results are required.

## Floating point contracts

Exact equality is appropriate for exact sentinels or contracts requiring bit-independent numeric equality; it is often inappropriate for approximate computed values. For approximate equality, choose absolute and relative tolerances from the domain and magnitude, and define behavior for NaN and infinities. A universal epsilon is not justified by the float type alone.

NaN compares unequal to itself, and ordered comparisons with NaN are false. An error check using only `abs(got-want) > tolerance` can therefore accept NaN accidentally. Handle non-finite values explicitly when finite results are required. For exact decimal money, prefer integer minor units or a suitable decimal representation; math/big.Float provides adjustable binary precision, not exact decimal semantics by default.

## Resource lifetimes and cleanup failures

Determine whether the function owns a resource before closing it; io.Reader alone does not grant permission to close a caller-owned stream.

defer executes on function return, not at the end of a loop iteration. When resources should be released per item, use a helper scope or explicit cleanup that covers every exit.

Preserve write, flush, and close errors that can affect the promised result, without letting a cleanup error erase the primary failure. Use a named `err` result and join the close error into it (errors.Join needs Go 1.20+):

```go
defer func() {
    if closeErr := f.Close(); closeErr != nil {
        err = errors.Join(err, fmt.Errorf("close %s: %w", path, closeErr))
    }
}()
```

For buffered output, flush before closing the underlying resource. Keep both failures if both occur. Successful Close alone is not a durability guarantee; use the required synchronization and commit protocol if durability or atomic replacement is part of the contract.

For HTTP responses, close each acquired response body according to the client's ownership contract, including unsuccessful status paths. Draining for connection reuse must be bounded by the application's policy, not an unlimited read of arbitrary response data. For batches and shutdown, attempt every required release even if one fails, labeling each failure with its resource and operation.
