---
name: golang-debugging
description: 'Diagnoses Go failures to a verified root cause. Use when debugging Go bugs or crashes: panics and stack traces, wrong results, flaky or unexplained test failures, hangs, deadlocks, races, build failures, regressions after a commit or deploy, or production incidents and error spikes. Not for writing tests for understood behavior (golang-testing), benchmarking or analyzing latency, CPU, memory or GC costs (golang-performance-engineering), or reviewing code for bugs with no failure reported (golang-correctness).'
---

# Go Debugging

Give the developer a reproducible diagnosis: failing conditions, causal evidence, and verification that a repair addresses the original failure.

## Evidence before repair

Preserve expected versus observed behavior, exact error, inputs, revision, and environment. Seek a faithful reproduction before changing production code. When evidence is missing, request it and give a conditional next experiment. Missing access limits execution, not useful advice; label assumptions and unrun checks.

An unresolved diagnosis ends with one concrete experiment: **suspected mechanism, controlled change or observation, predicted result, and what a contrary result would mean**. Name the actual condition to vary; “reproduce, trace, test a hypothesis” or a list of tools leaves the developer to design the experiment. Even brief advice needs this connection. Supplied evidence that already establishes the cause needs explanation and verification instead.

Change one hypothesis at a time and record its result. Remove unsuccessful experimental edits without disturbing the user's work. Repeated failed fixes call for a discriminating experiment before another patch; their number alone does not establish a broken architecture.

Trace the symptom through callers, state, and ownership to the violated contract. Check upstream guarantees and dependencies; a suspicious pattern alone does not establish causality.

## Repair and handoff

For a requested repair, make the smallest justified change and rerun the original reproduction and relevant surrounding checks. Add a regression test that fails on the original defect for the intended reason, shown without reverting unrelated edits; when no test can trigger the failure deterministically, say so. Do not conceal failures through weakened assertions, retries, or longer sleeps.

Report causal evidence, commands and results, changed behavior, and uncertainty. Urgent recovery may precede diagnosis. Retain evidence unless capturing it would delay mitigation, verify recovery, and name the later evidence or experiment needed to investigate the still-unconfirmed cause.

When the open question becomes latency, CPU, memory or GC cost, invoke the `golang-performance-engineering` skill if available, passing the symptom, workload, revision, environment and captured evidence. Without it, state the measurement needed rather than inventing a performance conclusion.

## Focused references

Read the matching reference before advising on its diagnostic problem, including when access is missing. Use the project's Go version and available tools.

| Diagnostic question | Reference |
| --- | --- |
| Isolating failures, unexplained flakes, environment differences, regression bisection | [Reproduction](references/reproduction.md) |
| Panics, data races, deadlocks, goroutine lifetime, inspecting runtime state | [Runtime](references/runtime.md) |
| Compiler, toolchain, build tags, CGO, configuration and dependency failures | [Build and environment](references/build-and-environment.md) |
| Live incidents, bounded evidence capture, existing telemetry and mitigation | [Production](references/production.md) |
