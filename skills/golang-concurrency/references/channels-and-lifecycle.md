# Channels and lifecycle

Give goroutines an observable completion path as well as a stop signal. A WaitGroup waits but does not cancel; a context cancels but does not join.

## Channel contracts

- Expose receive-only or send-only channels according to the caller's role. Designate one closer who can prove all sends have ended; with multiple producers this is often a coordinator waiting for every producer.
- A consumer that stops early signals cancellation rather than closing the data channel. Closing a channel is unnecessary when no receiver needs an end-of-stream signal and all users can terminate otherwise.
- A closed channel remains ready. Check the receive's ok result; return or disable an exhausted input by setting the local channel variable to nil. Sending to a nil channel blocks; closing one panics.
- Choose capacity from handoff, burst, and backpressure requirements. Zero capacity gives a rendezvous, not a universal performance default. A buffer cannot fix a missing shutdown path.
- A channel send copies the value, not referenced storage. Transfer exclusive ownership, share immutable data, copy to the required depth, or synchronize later mutation. Pointers can safely transfer ownership; value structs containing slices can still race.

## Cancellation and progress

A select chooses among ready cases without giving cancellation priority. A preliminary context error check avoids starting work when cancellation is already observed, but does not atomically prevent cancellation racing with admission. Define any stronger cutoff with explicit coordination.

Select send operands are evaluated before a case is selected. Putting expensive work inside a send expression does not make that work cancellable. Perform it under its own cancellation contract before selecting on the result send.

Default cases are appropriate for deliberate nonblocking operations. In a waiting loop they can create a busy spin. Context-free finite work need not acquire a context merely to satisfy a rule about every select.

## Timers

Define whether a timer measures inactivity or a fixed periodic interval; a ticker is not an inactivity timer. Repeated time.After calls can add allocation churn in hot loops. Reuse a timer when warranted and reset at the intended activity boundary.

Go 1.23 timer semantics depend on the main module's Go version and GODEBUG settings. Under the new semantics, Stop/Reset prevent subsequent receives of stale timer values; older channel timer semantics require coordinated stop/drain/reset by the sole timer owner. An unconditional drain after Stop returns false can itself block. Do not label all unreferenced timers as permanent leaks on current Go versions.

## Panic and completion boundaries

Recover only at a deliberate isolation boundary whose contract permits continuing. Recovery must run in the panicking goroutine and must report the failure to its owner; silently recovering can turn incomplete work into apparent success. A handler's recovery does not catch panics in goroutines it spawned.

Verify saturated output cancellation and multi-producer closure. Existing goleak checks can supplement race tests; scope known long-lived goroutines narrowly, since broad exclusions hide leaks.
