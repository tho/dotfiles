# Concurrency in tests

Make completion and ownership observable. A sleep that happens to pass today does not establish that a goroutine reached the intended state.

## Parallel isolation

Use `t.Parallel` only for cases that own independent mutable state and external resources. Account for shared globals, ports, environment variables and working directories. `t.Setenv` is incompatible with parallel tests or parallel ancestors.

Create testify helpers from each subtest's `t`. Go 1.22 loop-variable semantics remove the old per-iteration capture trap for variables declared by the loop; older module language versions need an explicit per-iteration copy. Neither case makes shared pointers or slice backing arrays independent.

Use `t.Cleanup` for resources needed by parallel children: parent-function defers run before those children resume, whereas parent cleanup waits for subtests to finish.

## Workers and timing

Workers send errors and values back to the test goroutine through a channel or other synchronized result. Join workers before the test ends, then use `require` and `assert`. A worker's fatal assertion can terminate that worker while leaving the test blocked forever waiting for its result.

Prefer explicit completion channels, injected clocks, or `testing/synctest` for timing-sensitive behavior. Stable `synctest.Test` and `synctest.Wait` require Go 1.25 or later; use an injected clock or explicit synchronization for earlier supported versions unless the project deliberately uses an experimental API.

Inside a synctest bubble, fake time advances when its goroutines are durably blocked; `synctest.Wait` lets other goroutines reach that state before assertions. It does not force a specific scheduler order or make arbitrary network I/O deterministic. Keep real external I/O outside assumptions about synthetic time.

Bound waits and arrange cancellation plus joining even if assertions fail. Use the test runner's timeout as a final backstop rather than installing a background goroutine that panics to abort the process. Polling checks must synchronize access to shared state and have a finite deadline.

## Verification

Run focused tests with `-race` for relevant concurrent behavior. A clean run checks only exercised paths; it does not prove absence of races. Use repeat runs or `-shuffle=on` to investigate independence when the changed behavior warrants it, preserving a failing seed.

For goroutine-owning packages, consider `goleak.VerifyTestMain` for package-wide leak checks. Per-test `VerifyNone` conflicts with unrelated goroutines from parallel tests. Close owned resources and join workers before checking leaks. Any ignored stack needs a known owner and a reason; blanket ignores can hide the leak being tested.
