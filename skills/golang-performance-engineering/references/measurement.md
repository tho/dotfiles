# Measurement and comparison

The result must distinguish a code effect from workload, compiler, and machine effects. A benchmark is evidence about the work it actually executes, not an application's general speed.

## Benchmark validity

Follow existing repository conventions; for new benchmark files, use the source basename with a `_bench_test.go` suffix and keep benchmark order aligned with the source.

Include representative sizes and adverse cases so an improvement on a tiny fixture does not hide scaling regressions. Measure a focused operation to diagnose cost and a representative integration workload when making service claims.

For Go 1.24+, prefer the exact `for b.Loop() { ... }` form for sequential benchmarks. It excludes setup before the loop and cleanup after it and protects work in its body from inappropriate elimination. Keep existing `b.N` benchmarks when appropriate for compatibility or comparison, excluding setup with `b.ResetTimer()` and making results observable where elimination is possible. Do not change benchmark form in only one side of an optimization comparison. Compiler behavior still depends on the toolchain; verify implausibly fast results rather than diagnosing dead-code elimination from a timing alone.

Use `b.ReportAllocs()` or `-benchmem` for allocation counts and bytes. Reset mutable inputs between operations when the operation consumes or changes them; a warmed cache, exhausted reader, or already-sorted input can silently change the question.

For concurrent operations, use `b.RunParallel` with worker-local state and `pb.Next()`, not a nested `b.Loop`. Report `GOMAXPROCS` and contention levels.

## Controlled capture

Record the code revision, dirty diff if any, fixture identity, Go version, OS, architecture, CPU, `GOMAXPROCS`, CPU quotas, build tags, PGO settings, and relevant environment. Toolchain or dependency upgrades require rebuilding the baseline under the same conditions when isolating a code change.

These command examples use an illustrative package and benchmark; substitute the real target and write results into a fresh investigation directory. Check each exit status and retain stderr separately from raw benchmark output.

```bash
go version
go test -run='^$' -bench='^BenchmarkParse$' -benchmem -count=10 ./pkg/parser > baseline.txt
# After the candidate change, with the same workload and environment:
go test -run='^$' -bench='^BenchmarkParse$' -benchmem -count=10 ./pkg/parser > candidate.txt
benchstat baseline.txt candidate.txt
```

Ten samples per case is a starting point, not a guarantee of significance. Choose duration and sample count for the expected effect and observed noise.

Run baseline and candidate serially on the same host without other benchmark or build workloads. A quiet local machine can be more reliable than shared CI. If conditions drift, build each version's test binary with `go test -c`, then alternate or randomize serial executions with the same `-test.run='^$'`, `-test.bench`, and measurement flags. Use fresh output files so older samples are not mixed in. Compilation is outside the benchmark timer; prebuilding controls surrounding load and makes interleaving practical, not a correction to reported compilation time.

Prepare competing implementations in isolated worktrees only when useful and authorized. Record their revisions and measure serially. Remove only disposable worktrees created for the experiment after preserving evidence and confirming no work would be lost.

## Interpret benchstat

Read the median, confidence interval, sample count, warnings, and comparison together. Check the unit before calling a positive delta a regression.

- Keep `~` rows in the report.
- Unequal sample counts are not automatically invalid; explain missing rows or failed runs and heed the tool's statistical warnings.
- Avoid collapsing workload dimensions such as input size or concurrency into a geomean that hides a critical regression.

For filters, the base benchmark name omits `Benchmark`: `benchstat -filter '.name:Parse' baseline.txt candidate.txt`. Use `benchstat -h` for the installed version's projections and filtering syntax. The first input is the common baseline.

## Verification and evidence

Run tests that exercise changed semantics, error paths, ordering, ownership, and concurrency as relevant. Race instrumentation belongs in correctness verification, not benchmark comparisons.

Report both time and allocation effects and any unmeasured tradeoffs. Put relevant benchstat rows, including inconclusive or regressing rows, in a requested PR or commit description; do not create a commit merely to store evidence.
