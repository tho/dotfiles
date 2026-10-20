# Metrics and correlation

Define whether a count represents requests, attempts, retries or jobs so an error ratio has the same population in numerator and denominator.

## Registration and dimensions

Create collectors once per owning component and register them with an explicit registry when isolation matters. Avoid global auto-registration in reusable libraries and repeated construction paths. Register Go and process collectors explicitly with custom registries; serve the registry actually used by the application. Check what the installed collector exports rather than assuming host or container metrics are present.

Budget series as the product of label values, replicas and histogram buckets, not a fixed maximum for one label. Use router templates, normalized methods and finite outcome classes. Map unmatched routes and arbitrary methods to bounded fallback values. Exclude raw paths, query strings, user IDs, request IDs and trace IDs from metric labels.

Count failures as well as successes. For HTTP middleware, preserve ResponseWriter capabilities such as flushing and hijacking or use established instrumentation. Streaming request duration and time to first byte are different measurements.

## Histograms and queries

Choose classic histogram buckets around the service's latency objective and expected range; an SLI at 300ms requires a 0.3-second bucket. Native histograms require compatible client, server and query support. Summary quantiles cannot be averaged or aggregated into fleet percentiles.

Apply rate before aggregating so counter resets are handled per series. Preserve le for classic histogram quantiles. For a fleet mean, divide aggregated _sum rates by aggregated _count rates; averaging per-instance means biases toward quieter instances.

This latency SLI example assumes a service label on the named metric; match actual names and labels before use:

```promql
sum by (service) (rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
/
sum by (service) (rate(http_request_duration_seconds_count[5m]))
```

Keep query examples near declarations or in maintained rules so name, label and bucket changes have discoverable consumers. Keep denominator-zero and absent-series behavior explicit; no traffic is not proof of health.

Exemplars may attach a valid sampled trace ID to an observation without making it a series label. Verify OpenMetrics negotiation, exemplar storage and the backend trace link. Observe the value exactly once whether or not exemplar support is available.

Check a scrape after representative successes and failures, isolate registries in tests, and exercise arbitrary paths and methods to confirm bounded series growth. Match dashboard units and grouping to the recorded metrics.
