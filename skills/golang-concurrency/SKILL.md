---
name: golang-concurrency
description: 'Designs Go concurrent work and context lifetimes. Use when writing or reviewing Go code with goroutines, channels, select, sync.Mutex/RWMutex, atomics, sync.Map, WaitGroup, errgroup, singleflight, worker pools or pipelines; preventing goroutine leaks or data races; or managing cancellation, deadlines and context propagation. Not for telemetry SDK setup or exporter lifecycle, even with context or timeouts (golang-observability), code merely accepting ctx, general defensive coding, or production incident diagnosis.'
---

# Go Concurrency

Help Go developers make concurrent work and context lifetimes explicit enough for callers and reviewers to rely on.

Use the project's declared Go version and dependency APIs. Preserve the requested completion contract: immediate cancellation, graceful draining, and durable delivery are different promises.

## Correctness bar

- Give each goroutine an owner, a termination condition, and a way to observe completion. Cancellation signals a request to stop; it does not wait for work or force a blocked dependency to return.
- Define who may mutate each shared value and who may close each channel. A channel handoff or shallow struct copy does not remove aliases to slices, maps, or pointers.
- Bound active work and queued work. Make blocking sends, receives, and admission waits cancellable when their lifetime belongs to the caller.
- Preserve the caller's context through API boundaries, deriving narrower deadlines as needed. Release cancellation resources at their intended scope or explicitly transfer ownership.
- Treat detached work as a separate owned lifetime. Preserving context values with WithoutCancel provides neither a shutdown policy nor durable execution.

## Focused references

Read only the references relevant to the task. Paths are relative to this skill's directory.

| Concern | Reference |
| --- | --- |
| Goroutine ownership, channel closure, cancellation, timers, panic boundaries | [Channels and lifecycle](references/channels-and-lifecycle.md) |
| Locks, atomics, maps, pools, once, wait groups, duplicate suppression | [Synchronization](references/synchronization.md) |
| Bounded admission and errgroup limits, workers, cancellable stages, fan-out/fan-in, backpressure, graceful draining | [Pipelines](references/pipelines.md) |
| Cancel ownership, deadlines, AfterFunc, detached work | [Context lifetimes](references/context-lifetimes.md) |
| Context parameters, HTTP/database calls, retries, metadata, trace propagation | [Context boundaries](references/context-boundaries.md) |

## Evidence and handoff

For implementation, exercise affected cancellation, early-return, and completion paths; run focused race checks where supported. A passing race detector covers only executed paths and does not prove freedom from deadlocks or leaks. Verify shutdown with explicit completion signals or the project's leak checks, not sleeps.

Support concurrency findings with a reachable interleaving or lifetime failure. Report checks actually run and remaining uncertainty.
