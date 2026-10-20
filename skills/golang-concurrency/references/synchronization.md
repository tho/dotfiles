# Synchronization

Choose synchronization from the invariant that must hold, not from the primitive's name. Document which lock or ownership rule protects related fields and keep reads and writes under the same rule.

## Shared state

- A plain map with a mutex is a useful baseline. Concurrent unsynchronized map access with a writer is unsafe; a runtime fatal error is possible but is not a guaranteed race detector.
- RWMutex permits simultaneous readers, but is not inherently faster. Do not recursively acquire RLock, because a waiting writer blocks the second RLock and deadlocks; do not upgrade it to Lock, because Lock waits for the holder's own read lock. After releasing a read lock and acquiring a write lock, recheck assumptions that could have changed.
- Keep critical sections bounded. Move I/O, callbacks, and channel waits outside a lock when the invariant permits; otherwise explicitly account for lock order and blocking. Copying protected state before unlocking may require deep copies.
- Typed atomics, available from Go 1.19, work for independent counters, flags, and published pointers. They do not make a multi-field invariant atomic or protect mutation of a pointed-to object.
- sync.Map specializes in write-once/read-many entries and largely disjoint key sets. It has Range, but Range is not a consistent snapshot. Prefer a typed map plus a lock for cross-key invariants; justify performance claims with measurements.
- Do not copy mutexes, WaitGroups, Once, sync.Map, Pool, or typed atomic values after first use. Watch value receivers and copies inside containing structs.

## Completion and initialization

WaitGroup tracks completion without error propagation. With Add/Done, register work before it can race with a Wait that sees zero. Reuse a group only after earlier Wait calls have returned. Go 1.25 adds WaitGroup.Go; its function must not panic, because nothing recovers in the new goroutine and the process crashes. Neither form supplies cancellation.

errgroup combines waiting and first-error reporting; WithContext also cancels siblings. Its derived context is canceled when Wait returns, including successful completion. Use the original parent for subsequent work that must continue after the group.

sync.Once finishes after its first call even if that call panics; it is not a retry mechanism. Go 1.21 OnceFunc, OnceValue, and OnceValues simplify cached initialization, including cached failures. Choose explicitly whether a failed initialization should be retried. Keep close errors observable if repeated Close calls must report the original result.

## Reuse and duplicate suppression

sync.Pool holds expendable temporary objects. Get can ignore stored entries, and the runtime can discard entries at any time. Establish a clean-state invariant on acquisition or return; do not assume Get yields zeroed state. Relinquish every alias before Put, including slices referencing a buffer's storage. Pool pointers such as *bytes.Buffer, because putting a non-pointer value boxes it into an interface and allocates. Pools are unsuitable for durable state or resources requiring deterministic closure.

singleflight suppresses concurrent calls for a key; it does not cache completed results. Shared results still need an ownership policy. Do with a caller's context makes all waiters depend on that caller's cancellation. For independently cancellable waiters, DoChan permits selecting on each waiter's context, but that does not cancel the underlying function. Give the shared computation a separately bounded, owned lifetime. Forget allows a subsequent duplicate to start; it is not cancellation.
