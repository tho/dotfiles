# Pipelines and bounded work

Define what success means when upstream fails or a consumer stops early: partial results, all-or-nothing completion, or graceful draining. The owner needs a completion/error path in addition to any result channels.

## Admission and errors

For a finite batch with first-error cancellation, errgroup.WithContext plus SetLimit is often sufficient. SetLimit bounds active functions; it does not bound all storage elsewhere or interrupt a blocked Go admission call when the context is canceled. Already admitted tasks must cooperate with cancellation, and the producer should stop submitting once it observes cancellation. Do not change the limit while tasks are active, because SetLimit panics, or recursively submit blocking work into a saturated group, because the submitter holds a slot while waiting for one and deadlocks.

When admission must wake on cancellation, use a fixed worker set with a cancellable dispatcher or a context-aware semaphore acquired before spawning. Acquiring a semaphore inside each new goroutine bounds execution but leaves goroutine creation unbounded. Release every acquired slot on exit. If submission aborts, cancel when appropriate and join already-started work before returning.

WaitGroup plus explicit error coordination can be correct; errgroup is a simpler default when its contract fits, not a requirement to replace a working specialized pool. Use worker-local state, custom scheduling, or separate draining signals when the workload needs them.

## Stage contracts

- Make every potentially indefinite input receive and output send interruptible by the stage's stop mechanism. Guarding only the output send does not release a stage waiting on idle input.
- Each stage closes its output only after all its senders have ended. For fan-in, a coordinator joins forwarding goroutines before closing the merged output.
- Forward errors to the owner and cancel upstream when downstream exits early. Buffered results alone do not ensure upstream stops or the owner observes completion.
- Distinct goroutines may write distinct elements of a preallocated results slice if nobody reads before joining and no shared slice header is mutated. Concurrent append needs separate coordination.
- Treat queue capacity, overload, and shutdown as one contract. Bound queued and active work; specify whether a full queue waits, rejects, drops, or persists work. State how admission stops, whether accepted jobs drain or abort, who closes the queue after all senders stop, and how the owner joins workers. Capacity alone does not establish the lifetime of retained jobs or blocked senders.

## Sequential alternatives

Use ordinary loops or Go 1.23 iterators for sequential in-memory transforms that do not benefit from parallel work. A CPU-bound computation may benefit from parallelism if sufficiently large; being CPU-bound alone is not grounds to reject concurrency. Channel stages are useful for overlap, independent producers, or actual parallel processing. Reactive-stream libraries are optional architecture choices, not prerequisites for a pipeline.

## Evidence

Exercise empty input, first and later worker errors, cancellation while admission is blocked, early consumer exit, and graceful draining. Assert the maximum active work and that all started work finishes or stops before the owner's promised completion. Cancellation is cooperative, so a dependency that ignores its context can still prevent a join from returning.
