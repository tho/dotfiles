# Optimize the diagnosed bottleneck

Choose a candidate because it addresses observed cost. Preserve behavior and compare against the unchanged baseline.

## Work and algorithms

Repeated scans may justify an index or a different algorithm. Benchmark across input sizes and include index construction, reuse, and memory in the comparison. Ordinary repeated slice append has amortized linear total growth cost; preallocation reduces allocations and copying rather than generally changing it from quadratic to linear.

| Observed cost | Candidate | Tradeoff or semantic check |
| --- | --- | --- |
| Repeated membership scans | Build a map once or sort for repeated queries | Construction cost, extra memory, ordering, key equality |
| Repeated string concatenation | `strings.Builder` or byte buffer | Capacity estimates and ownership of returned data |
| Repeated regexp/template compilation | Compile immutable patterns once | User patterns return errors; caches need bounds |
| Repeated fetches for the same key | Bounded cache and optionally `singleflight` | Freshness, invalidation, tenant-aware keys, cancellation, error handling |
| Tiny pure computation with small input domain | Lookup table | Table footprint, cache behavior, exhaustive correctness |
| Proven iterator/closure overhead | Direct loop, early exit, or fused operations | Preserve order, side effects, and error behavior |

`singleflight` suppresses concurrent duplicate work; it is not a cache. Recheck a cache inside the shared operation where necessary, handle errors before asserting result types, and distinguish cancellation of one waiter from cancellation of shared work. Choose cache capacity and eviction from the working set. Benchmark misses and concurrent access, not only warm hits.

## Allocations and retention

For allocation churn, reduce construction and copies before adding pools; size hints do not guarantee a single allocation. A zero-size set value can avoid storing booleans, but total map memory depends on implementation and capacity, not just entry count times value size.

Reuse owned slices with `s[:0]` only while no caller needs the old contents. Clear obsolete pointer-bearing elements when retention matters. A small subslice or substring can retain a large backing allocation; clone the retained portion when the lifetime and memory savings justify a copy. Deleting map entries need not return capacity; rebuilding a sparse, long-lived map is a candidate with temporary memory and CPU costs.

Use typed APIs, values, or generics when measured boxing or pointer scanning is costly. Confirm allocation changes with compiler diagnostics and benchmarks. Preserve identity, mutability, nil behavior, and API compatibility. Do not assume every string/byte conversion allocates.

`sync.Pool` is for expendable temporary objects; entries can disappear at any time. It is neither durable storage nor a capacity-bounded cache. Reset state, clear retained references, and keep buffers exclusively owned until the consumer finishes. Copy results before returning storage to a pool when ownership would otherwise escape. Set a workload-derived retained-capacity policy for unusually large buffers; there is no universal 32 KiB pooling cutoff. Compare allocation savings with retained heap and concurrency behavior.

Unsafe zero-copy conversions require a demonstrated need and an explicit lifetime and mutability argument. Prefer safe APIs when their measured cost meets the target.

## CPU and memory layout

Follow expensive runtime calls back to application sites. Reduce copying, unnecessary reflection, repeated formatting, or redundant work where measured. Replacing `reflect.DeepEqual` with typed equality can change nil-versus-empty, floating-point, or recursive behavior; test the intended semantics.

Keep expensive log-argument construction behind an enabled-level check where appropriate; typed `slog` attributes can reduce overhead but arguments still evaluate before the call.

For memory-bound loops, compare contiguous storage and traversal order; Go arrays are contiguous but separately allocated slice rows need not be. Choose structure-of-arrays only when access patterns benefit. Struct reordering can reduce padding or pointer scanning but may affect public layouts, reflection, serialization, or unkeyed literals. Verify size and alignment (for example with `fieldalignment`) on supported architectures.

False sharing concerns independent writes on the same cache line, not a data race. Test scaling and hardware counters (for example `perf`) before adding padding; cache-line size is architecture-dependent. Multi-accumulator arithmetic or reordering can change floating-point rounding and overflow-sensitive behavior.

SIMD candidates need a CPU-bound numeric hotspot. Prefer proven libraries where applicable. Architecture tags alone do not establish AVX2 support: use feature detection and a fallback or an explicit deployment CPU target. Building on a faster machine does not automatically select that machine's instruction set. Measure end-to-end value and maintenance cost before adding assembly.

## I/O, networking, and concurrency

When latency is dominated by an external component, investigate query plans, round trips, queueing, or connection reuse before tuning local allocations. CPU profiles alone do not locate off-CPU time.

Reuse HTTP clients and transports. Clone `http.DefaultTransport` when adjusting defaults, then set workload-appropriate timeouts and pool limits. `MaxIdleConnsPerHost` limits idle reuse; it does not cap active connections. `MaxConnsPerHost` caps connections, and HTTP/2 multiplexing makes connections different from concurrent requests. Confirm actual dialing and reuse before diagnosing pool exhaustion from idle read goroutines.

Close response bodies on every path. Reading HTTP/1 response bodies to EOF can permit reuse, but draining arbitrary unbounded bodies costs time and bytes; respect size limits and deadlines. Tune streaming server/client timeouts to the operation rather than copying fixed values.

Use streaming for bounded working memory where the format permits it. A JSON decoder can still buffer a whole value; incrementally decoding array elements requires consuming the opening token, iterating elements, and checking the closing token and trailing input policy. Scanner buffers have token limits and scanner bytes are reused; check scan errors and copy bytes that outlive the iteration.

For JSON hotspots, compare typed custom marshaling, maintained code generators, or alternate libraries with representative payloads. Check numbers, escaping, duplicate keys, invalid UTF-8, unknown fields, and error behavior. Verify experimental or version-dependent APIs against the selected Go release; do not assume a new implementation is the default or compatible.

Batch syscalls, cgo crossings, or external operations when per-call overhead dominates. Bound batch size and residence time, preserve transaction/error semantics, and flush remaining work on close or cancellation according to the contract. Handle write and flush errors. Reuse batch memory only when the consumer no longer retains it.

Concurrency can overlap waits or distribute CPU work, but throughput is limited by available resources. Use bounded queues, cancellation, and clear channel ownership; include queue memory and tail latency in the comparison. Shrink measured critical sections or partition shared state before reaching for lock-free structures. For scheduling delays, investigate quotas, oversubscription, and actual trace evidence.

## Runtime and PGO

GC tuning trades CPU, memory, and latency. Reducing measured allocation pressure may remove the cause; raising `GOGC` may reduce GC work at the cost of more memory. Lowering it does not guarantee shorter tail latency. Evaluate the service objective and container headroom together.

`GOMEMLIMIT` is a soft limit for Go-managed memory, not an RSS limit or an OOM guarantee. Leave measured headroom for cgo, mappings, and other memory outside its accounting. A limit near the live working set can induce heavy GC or be exceeded. Do not transplant a fixed percentage without measuring that headroom.

Check actual `GOMAXPROCS`, affinity, CPU quota, throttling, Go version, module language version, and overrides. Go 1.25 introduced container-aware defaults; effective behavior depends on configuration and compatibility settings. Explicit overrides may disable automatic adjustment. Validate rather than assume either host CPU count or quota is always used.

For PGO, collect a representative CPU profile and explicitly compare builds with PGO disabled and with the chosen profile. The main package's `default.pgo` is auto-detected by supported toolchains; record the profile identity and build settings so it does not silently contaminate the baseline. Confirm gains across important workloads and refresh stale profiles.
