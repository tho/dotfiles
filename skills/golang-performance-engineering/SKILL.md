---
name: golang-performance-engineering
description: 'Measures and improves Go performance with reproducible evidence. Use when writing or comparing benchmarks (benchstat, b.Loop), interpreting pprof profiles or execution traces (go tool trace), investigating latency, CPU, allocation, escape or GC costs, tuning GOGC, GOMEMLIMIT, GOMAXPROCS, PGO, sync.Pool or HTTP transports, assessing an optimization, writing a performance PR/review conclusion, or gating benchmark regressions in CI. Not for diagnosing failures, hangs or behavioral regressions (golang-debugging), routine instrumentation or alerting (golang-observability), or release notes (golang-documentation).'
---

# Go Performance

Give the developer a performance decision they can act on safely and reproduce: what the evidence supports, what could invalidate the recommendation, and what would establish acceptance. Answer an explanation-only request directly; a recommendation or review conclusion also needs the relevant conditions and verification below, even when brief.

## Answer contract

Connect each proposed change to a measured cost; without measurements, label it a hypothesis. Distinguish computing from waiting, allocation churn from retention, and benchmark throughput from request latency.

Recommendations and optimization reviews have three compact parts: **verdict and scope** (with measured tradeoffs against the target), **preconditions**, and **acceptance evidence**. Short clauses suffice. Preconditions name the measured hotspot or the profile needed to establish it, plus the applicable conditions below. Acceptance evidence names correctness checks and a representative before/after experiment with input shape and concurrency, even when no project is available to execute them.

| Change or claim | Conditions the reader needs |
| --- | --- |
| Reuse, pooling, or caching | Ownership, lifetime, reset/invalidation and bounds; cache keys include all result-affecting inputs and tenant/security scope. Test changed behavior, then compare representative time, allocations and retained memory. |
| HTTP connection tuning | Reuse clients/transports and preserve defaults (clone the default transport when appropriate); verify dialing/reuse. Idle connection limits differ from active limits, and HTTP/2 multiplexes requests. Close bodies; bound draining and deadlines. |
| Runtime/resource tuning | Verify effective in-process settings, overrides and actual container limits before choosing values. Budget non-Go memory; the Go soft memory limit does not guarantee RSS or prevent OOM. Compare GC CPU, memory and latency under representative load. |
| Compiler or CPU-specific optimization | Inspect actual escape/inlining or emitted instructions. Receiver type does not guarantee inlining; bounds-check elimination does not prove SIMD. Check deployment CPU features and a fallback or explicit target, plus correctness and representative benchmarks. |
| Latency or service-impact claims | Parallel ns/op is aggregate throughput, not p99. Include completion of asynchronous work, record concurrency/GOMAXPROCS, and measure individual latency under representative load; a microbenchmark does not establish service impact. |

## Controlled comparison

Establish a representative baseline before changing code. Change one hypothesis at a time; compare candidates against that common baseline using the same workload, toolchain, build flags, hardware and concurrency. Measure serially on shared hardware, separate from profiling and race instrumentation. Predeclare follow-up sampling and confirm a selected winner on fresh data rather than retrying until significant.

Use repeated samples and `benchstat`. Retain raw results, including `~`: no detected significance proves neither improvement nor equivalence. For wide intervals, the follow-up recommendation includes concrete noise control: a quiet host, serial runs without competing builds, and interleaving to reduce drift, followed by a predeclared sample plan. More samples alone do not repair biased conditions. Judge practical effect and every acceptance constraint, not just the winning metric. Failed correctness or an unacceptable regression blocks acceptance.

## Decision and handoff

Even a short review conclusion identifies missing reproducibility evidence and unmeasured production impact. Supply or request the relevant revisions, commands, workload, toolchain/environment, raw results and correctness results; do not fabricate them. An inconclusive result remains inconclusive.

Keep this proportional: a sentence can name the missing evidence or next check. Interpret supplied results without executing new measurements. A requested commit/PR description carries the evidence; permission to commit or deploy is separate.

## References for unresolved details

Fetch external documentation only for uncertain or version-dependent behavior.

- [Measurement](references/measurement.md): benchmark construction, `b.Loop`, benchstat, and controlled capture.
- [Diagnosis](references/diagnosis.md): profile selection, waiting, traces, and compiler analysis.
- [Optimization](references/optimization.md): algorithm, allocation, CPU, HTTP, runtime and PGO candidates with tradeoffs.
- [Production](references/production.md): metrics, service validation, CI regression gating and alert examples.

Use the project's Go toolchain and `benchstat` from `golang.org/x/perf/cmd/benchstat`; check availability and pin automation versions. Optional companions: `golang-debugging`, `golang-concurrency`, `golang-database`, and `golang-observability`.
