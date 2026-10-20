# Runtime failure diagnosis

Choose evidence that discriminates between causes. A stack shows where execution stopped; it does not by itself explain how invalid state arrived there.

## Panics and incorrect values

Preserve the panic and stack, then trace the failing value back to its origin, callers, and initialization. For a local executable, `GOTRACEBACK=all` includes other user goroutines on an unrecovered panic; it does not generate a dump of a healthy running process.

| Symptom or suspect | Evidence to seek |
| --- | --- |
| Non-nil error containing a nil pointer | Concrete type and value at the interface conversion; return a nil interface for success |
| Value unexpectedly changes after append | Slice lengths, capacities, shared backing array, and actual writer |
| Error lost between layers | Shadowed variables, ignored return values, wrapping and the caller's error comparison |
| Missing or truncated decoded data | Destination field visibility and types, checked decode errors, numeric conversion bounds |
| Resource exhaustion | Acquisition, ownership transfer, close/cancel path, and whether deferred cleanup waits for a long-lived function |

These are hypotheses, not universal fixes. For loop capture, check the module language version and whether variables are declared by the loop or assigned to existing variables. For timers, check effective Go timer semantics before attributing retention to an obsolete behavior. Allocation churn alone is not proof of a leak.

## Data races

Run a focused failing workload with `go test -race`, or a representative instrumented executable where supported. Read both conflicting access stacks and goroutine creation stacks. Identify the shared location and missing synchronization or ownership transfer; an unrelated race report does not automatically explain the reported failure.

The detector observes executed paths. A clean run is not proof of race freedom, and it does not rule out deadlocks or logical ordering bugs. Distinct independently accessed fields do not race merely because they share a struct. Check concurrent accesses to each location, including whole-struct reads and copies.

## Hangs, deadlocks, and goroutine lifetime

Collect stacks from a bounded test timeout, an existing protected goroutine diagnostic endpoint, or targeted `runtime.Stack` instrumentation. For a suspected leak, compare captures over repeated completed work and a quiescent period. Let the tooling group and diff: `debug=1` goroutine output or `go tool pprof -traces` merges identical stacks with counts, and `go tool pprof -diff_base=before.pb.gz after.pb.gz` shows which grew. Read `debug=2` detail only for the groups that persist, then identify what should release each wait.

A goroutine waiting on a channel or mutex can be normal. Establish a wait cycle, a missing completion event, or work that persists beyond its intended lifetime. A growing goroutine count is a signal, not the causal explanation. A service can be partially deadlocked while the runtime's global deadlock detector stays silent.

Check cancellation propagation, abandoned receivers, lock order, and whether producers can complete when consumers exit. Closing every channel is not a general fix; some channels need no closure, and closing a channel still in use by senders can panic. If the project already uses a leak checker, compare failures against its documented background goroutines rather than automatically adding exclusions.

## Targeted debugger use

Use the simplest observation that can settle the hypothesis. If state cannot be inferred from a reproduction or targeted logs, an available compatible Delve can run `dlv test ./path/to/pkg` or `dlv debug ./cmd/app`. Break near the suspected transition and inspect values, stacks, and goroutines. Compiler optimization and debugger pauses can alter observability and timing; absence of a failure under the debugger is inconclusive.

Attaching to a live process can pause it. Establish acceptable impact first, and prefer existing captured evidence for an incident. Use a debugger only if one is already installed, and keep any debug listener local.
