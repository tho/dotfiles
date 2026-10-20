# Dependency wiring and lifetime

Give services the dependencies they use. Keep composition in application startup or dedicated wiring code so a maintainer can inspect construction, failure, and teardown without tracing service lookups through business logic.

## Manual injection first

Ordinary constructor calls are the default.

Construct dependencies before their consumers and clean up successfully acquired owned resources if a later constructor fails. The composition root normally owns shared pools and clients; consumers borrow them. Close dependents before the resources they need. A constructor receiving an existing resource should not silently assume ownership.

Keep request data and request contexts in operations or explicitly scoped objects. Shared application services must not retain request state. Stateless services can be shared; stateful services may require application, tenant, or request scope. Neither statefulness nor service count alone determines singleton versus transient lifetime.

Use eager validation/startup for dependencies necessary for readiness. Lazy creation can defer expensive optional work, but moves failures and latency to first use and needs concurrency-safe initialization. Name that tradeoff instead of preferring laziness universally.

## Choosing a library

Preserve an existing DI stack unless changing it is requested or justified. Compare actual graph maintenance, lifecycle coordination, debugging, and team constraints; a large graph can still be wired manually, and creating mocks or choosing a container is not evidence that the design became simpler. Check current maintenance status and the project's pinned library version before recommending adoption or emitting API calls.

| Approach | Resolution and tradeoff |
| --- | --- |
| Manual constructors | Ordinary compiler-checked calls, explicit ownership; the application maintains order and cleanup |
| Wire | Generates ordinary constructor calls and can propagate provider cleanup; generation validates the graph, while external readiness remains a runtime concern. |
| dig | Runtime provider graph resolution using reflection; no application lifecycle framework by itself |
| Fx | Built on dig, adds application lifecycle and modules; demanded graphs and startup hooks must be exercised, not assumed valid because compilation passed |
| samber/do | Typed generic registration/resolution with runtime graph lookup and lifecycle facilities; generics do not prove that registrations exist or eliminate dependency cycles |

Providers may use a container to resolve constructor arguments. Keep that lookup in wiring adapters; injecting the whole container into business services hides their dependencies. Named bindings or result groups resolve intentional multiplicity, not arbitrary cycles. Do not flatten a legitimate dependency chain merely because it is deep.

## Library-specific checks

- Wire: separate injector stubs with the wireinject build constraint; regenerate with the project's pinned command rather than editing generated output. Verify interface bindings, provider errors, and reverse-order cleanup, including partial construction.
- dig: check registration and Invoke errors; describe runtime graph validation accurately. Constructors should not launch background work that lacks an explicit owner.
- Fx: connect start/stop work through Lifecycle hooks, with bounded contexts. A successfully started hook owns resources it will later stop; a hook that fails midway must clean up its own partial work. Registering a provider alone need not instantiate it. Exercise the demanded graph and lifecycle in tests.
- samber/do: Injector, provider, scope, override and shutdown APIs differ between major versions. Use panic-based helpers only where startup panic is an intentional policy. Do not assume cloning a container deeply isolates already-created mutable services.

Official API sources: [Wire](https://github.com/google/wire), [dig](https://pkg.go.dev/go.uber.org/dig), [Fx](https://pkg.go.dev/go.uber.org/fx), and [samber/do](https://do.samber.dev).
