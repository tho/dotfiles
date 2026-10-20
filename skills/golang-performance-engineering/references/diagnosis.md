# Diagnose the measured cost

Match the tool to the missing evidence. CPU samples describe time executing, not a complete latency budget. Correlate service latency with external spans, load, CPU quotas, and waiting before deciding the Go hot path is responsible.

## Signal to evidence

| Observed symptom | Evidence to collect | Interpretation to test |
| --- | --- | --- |
| CPU saturation | CPU profile, flat and cumulative costs | Expensive computation, copying, allocation, or GC |
| Frequent allocations or GC CPU | Heap `alloc_objects` and `alloc_space` | Object churn versus byte volume |
| Growing retained heap | Comparable `inuse_space` snapshots | Retention under stable load, cache growth, or leaks |
| High latency with low CPU | Trace, goroutine stacks, external spans, optionally fgprof | Network wait, synchronization, queueing, or scheduling |
| Contended locks | Mutex and block profiles, trace | Long critical sections or excessive shared work |
| Runnable goroutines wait | Scheduler trace and CPU quota/throttling metrics | Oversubscription, throttling, or scheduling delays |
| Unexplained heap allocations | Compiler escape diagnostics for the hot package | Escape, copying, or allocation decisions |

`alloc_space` is cumulative allocated bytes, not peak live memory or RSS. `inuse_space` reflects sampled live heap associated with GC accounting; capture comparable GC states. Growth suggests investigation, not proof of a leak. Runtime allocation and scanning functions identify costs; follow their application callers to find an actionable cause.

## Capture and inspect

Capture profiles separately from baseline timing runs, using unique artifact names for each experiment. Keep the matching binary and source revision for symbolization. Start unfiltered: `-ignore` drops samples whose stacks match and can change conclusions; `-hide` changes presentation.

For heap growth, compare equivalent snapshots with `go tool pprof -top -inuse_space -base=heap-before.prof heap-after.prof`. For different runs, align workload and duration before interpreting cumulative profile deltas. Normalization changes the comparison to relative composition and can conceal total growth; it does not establish a speedup.

For local profile viewing, bind the UI explicitly to loopback, for example `go tool pprof -http=127.0.0.1:8080 cpu.prof`.

Mutex and block collection require sampling configuration. `runtime.SetMutexProfileFraction(n)` samples roughly one in n contention events; mutex stacks generally identify the critical section's end, not the blocked acquisition site. `runtime.SetBlockProfileRate(n)` samples synchronization blocking by time, with 1 recording every event. Detailed collection can perturb the workload. Block profiles do not measure every kind of I/O wait.

## Trace the timeline

```bash
go test -run='^$' -bench='^BenchmarkParse$' -trace=trace.out ./pkg/parser
go tool trace -http=127.0.0.1:8080 trace.out
go tool trace -pprof=sched trace.out > sched.prof
go tool pprof -top sched.prof
```

Other trace-derived profile types include `net`, `sync`, and `syscall`. Distinguish runnable time waiting for execution from synchronization or network waiting. GC concurrent marking and assist work are distinct from stop-the-world pauses. Use event labels rather than assuming UI colors are stable across releases.

Add `runtime/trace` tasks for an operation spanning goroutines and regions for phases within a goroutine when that association is missing. Bound capture duration and storage; overhead depends on workload. For intermittent problems, consider the flight recorder available in Go 1.25+, checking the installed API's retention and concurrency semantics. Capture the preceding window on a concrete trigger and serialize snapshot writes.

`fgprof` can complement CPU samples with goroutine wall-clock sampling. It and blocked stacks identify where time is spent waiting, not by themselves whether the remote service, connection management, or local queue caused the wait.

## Compiler evidence

Read the compiler's actual escape and inlining decisions (`-gcflags='-m -m'`) and emitted instructions (`-gcflags='-S'`, `GOSSAFUNC`) for the target version. Interface conversions and pointers do not invariably allocate; value receivers do not guarantee inlining and pointer receivers do not prevent it. Inlining can change escape behavior. Bounds-check elimination is not evidence of SIMD vectorization; inspect emitted instructions for that claim.
