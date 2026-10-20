# Alerts and dashboards

Give on-call operators a signal tied to user impact, with severity, scope, owner, a clear summary and a first response. Define eligible events and failures before writing an availability SLI; redirects, client errors and cancellations are policy decisions, not universally failures. Page for urgent actionable impact; route slower capacity trends to tickets.

## Queries and burn rates

For a 30-day 99.9% objective, a common illustrative fast-burn pair uses 14.4 times the 0.001 budget over both 5m and 1h. Aggregate replicas into matching label sets before division.

Example for counters with service and outcome labels, where outcome="error" means an SLI failure:

```promql
(
  (
    sum by (service) (rate(service_operations_total{outcome="error"}[5m]))
    or on (service) (0 * sum by (service) (rate(service_operations_total[5m])))
  ) / sum by (service) (rate(service_operations_total[5m])) > 14.4 * 0.001
)
and on (service)
(
  (
    sum by (service) (rate(service_operations_total{outcome="error"}[1h]))
    or on (service) (0 * sum by (service) (rate(service_operations_total[1h])))
  ) / sum by (service) (rate(service_operations_total[1h])) > 14.4 * 0.001
)
```

The fallback supplies zero errors only for services with observed totals. Zero traffic still has an undefined ratio. Handle low traffic, missing scrapes and a service disappearing separately; do not turn all absent data into healthy zeros. A traffic guard can suppress noise but may also suppress real failures in a quiet service, so define another way to detect their impact.

Use rate rather than irate for sustained alert conditions. Choose `for` durations with scrape interval, evaluation interval and detection budget in mind; an SLO window already smooths data. Latency SLIs need a matching histogram boundary.

## Runtime context and routing

Goroutine count alone does not establish a leak. Calibrate sustained growth or saturation to workload and limits. Go allocated heap divided by Go reserved memory is not container utilization; use the relevant container or process memory measurement against an actual limit, accounting for non-Go memory. A summary sample with quantile="1" is not p99. Inspect metric type and labels before choosing a query.

Dashboard imports need compatible exporter versions, labels, units and data sources. Pair symptom panels with traffic and deployment context, and link alerts to the relevant dashboard and runbook. External rule collections are starting points, not calibrated defaults.

Check Alertmanager routing, grouping, inhibition and repeat intervals against the intended receiver. Rule validation alone does not prove notification delivery.

Validate rule syntax and use promtool rule tests where available for healthy, firing, recovered, low-traffic, counter-reset and missing-series cases. Verify referenced metrics exist.
