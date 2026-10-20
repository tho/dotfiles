# Production validation and regression detection

Compare latency distributions, throughput, error rates, and resource cost under representative traffic, including load, concurrency, data shape, and warm-up behavior.

## Comparable evidence

Record deployment revision, instance type, CPU and memory limits, Go version, build settings, load, and investigation window. Compare baseline and candidate cohorts with matched traffic or controlled replay; raw before/after dashboards alone can confuse deployment effects with traffic or infrastructure changes.

Correlate CPU, heap, goroutines, GC, and external spans with the symptom. Low Go CPU with slow requests can mean local queueing, upstream latency, or throttling. Inspect host/container metrics where runtime metrics leave a gap. Report service results separately from benchmark results.

## Runtime and Prometheus metrics

`runtime/metrics` names are not Prometheus metric names. Exposed series depend on the Go release, client library, registered collectors, platform, and collector options. Inspect the application's actual scrape and metric types before writing queries. Enumerate runtime metrics with `metrics.All()` where necessary.

The following are common series and illustrative queries. Scope them to the intended service and instance; preserve labels when comparing cohorts.

| Question | Example expression | Limit |
| --- | --- | --- |
| Allocation volume | `rate(go_memstats_alloc_bytes_total[5m])` | Bytes allocated per second, not live-heap growth; normalize by work |
| Current heap | `go_memstats_heap_alloc_bytes` | GC sawtooth and workload affect it; compare GC states |
| GC cycle rate | `rate(go_gc_duration_seconds_count[5m])` | Check collector semantics; rate alone is not a universal alarm |
| Average reported GC pause | `rate(go_gc_duration_seconds_sum[5m]) / rate(go_gc_duration_seconds_count[5m])` | Zero cycles gives no useful mean; not total GC CPU or p99 |
| Goroutine growth | `delta(go_goroutines[1h])` | Correlate with load and lifecycle before calling it a leak |
| CPU consumed | `rate(process_cpu_seconds_total[5m])` | CPU cores consumed; compare with quota, throttling, and `GOMAXPROCS` |
| Resident memory | `process_resident_memory_bytes` | RSS and Go allocator accounting are different quantities |

Subtracting `go_memstats_sys_bytes` from RSS does not isolate C allocations: reserved, released, and resident memory have different accounting. Growing RSS with stable Go heap is a clue to inspect cgo/mmap, allocator behavior, and OS memory maps, not proof of a C leak.

For p99 from classic histograms, keep a revision/cohort label (and route labels where an aggregate hides regressions) in the `histogram_quantile` aggregation. Do not average summary quantiles across instances; native histograms need different queries.

Interpret `gctrace` with the runtime version's documentation. The three wall-clock phases describe stop-the-world sweep termination, concurrent mark/scan, and stop-the-world mark termination; the middle duration is not a pause. Heap arrows describe heap at GC start, at GC end, and live heap. GC CPU fraction, frequency, assists, and pauses answer different questions and require workload context.

## Temporary investigation

Select one representative instance or bounded cohort. Use existing application-supported controls for profiles, traces, and logging; arbitrary environment variable names do nothing unless implemented. A deployment-level environment change may roll all replicas, so use the platform's supported mechanism that actually targets the intended instance or cohort.

Choose capture length, trace retention, sampling rates, and scrape interval from the missing evidence and data budget. More detail can perturb the measured system. Keep diagnostics private, record changed settings, and restore temporary settings afterward. Continuous profiling tools such as Pyroscope or Parca can supply historical comparisons; validate their overhead for the workload.

## CI evidence and gating

Measure base and candidate serially in the same job on the same hardware and toolchain, with identical benchmark definitions and flags. Prefer isolated runners for small effects. Keep raw results, the environment record, and comparison output as artifacts. Cached baselines must match the current environment; a historical number from another runner is not a controlled comparison.

Use repeated measurements and benchstat with an explicitly chosen practical regression threshold. A successful benchstat process is not a pass/fail performance gate. Treat failed benchmarks, missing rows, insufficient samples, and noisy comparisons as invalid or inconclusive according to a documented policy; do not silently call them passes.

Possible tools include benchdiff for ref comparisons, gobenchdata for trends, or a project-specific benchstat workflow. Check the installed tool's current behavior. Tools such as cob that can reset checkouts belong in disposable clean checkouts, never a developer's dirty tree. Do not change host CPU governors, SMT, or system settings without authorization for the dedicated measurement host.

Check the bundled [alert examples](../assets/prometheus-alerts.yml) with `promtool` before use; an alert names an investigation candidate, not a leak.
