---
name: golang-observability
description: 'Provides routine production observability for Go services. Use when adding or reviewing structured logging (log/slog, zap, logrus or zerolog migration), Prometheus metrics (counters, histograms, label cardinality, PromQL), OpenTelemetry tracing (spans, propagation, sampling, exporters), trace IDs in logs, dashboards, or SLO burn-rate alerts and Alertmanager routing. Not for collecting or interpreting evidence for a specific performance problem, benchmarking, or optimization decisions (golang-performance-engineering), nor product analytics.'
---

# Go Observability

Give the service maintainer and on-call operator trustworthy signals they can use without this conversation: what is measured, how signals connect, what warrants action, and how to verify collection. Match the requested change or review to the existing stack and deployment; a narrow logging fix does not require a new telemetry platform.

## Operational contract

Preserve established metric names, log fields and trace semantics unless the task calls for migration. Treat changes to labels, buckets and fields as changes to dashboards, alerts and downstream consumers. Inspect the Go version and pinned instrumentation packages before choosing APIs; consult official documentation for unresolved version-dependent behavior.

Telemetry should expose service outcomes without changing them. Bound exporter queues, sampling, payload sizes and shutdown time. Account for unavailable collectors and dropped telemetry. Keep credentials, bodies and personal data out of default signals; opaque user identifiers can still be personal data. Restrict diagnostic and scrape endpoints to their intended operators.

Measure each completed operation once at its owner. Use bounded route and operation names; correlate individual requests through logs and traces rather than metric labels. Reuse existing middleware instead of duplicating its measurements or spans.

## Focused references

Read the references relevant to the requested work:

- [Logging](references/logging.md): structured fields, slog correlation, error ownership and logger migration.
- [Metrics](references/metrics.md): registries, cardinality budgets, histograms, PromQL and exemplars.
- [Tracing](references/tracing.md): SDK lifecycle, propagation, sampling and span outcomes.
- [Alerting and dashboards](references/alerting.md): SLIs, burn rates, missing data, runtime signals and actionable notifications; read Metrics too when writing queries.

## Completion evidence

For implementation, verify the affected path through its actual handler, registry or exporter: success and failure signals, label bounds, correlation and lifecycle behavior. Use focused checks suited to the change; report untested backend or deployment wiring explicitly. Do not claim a dashboard or alert works from a code snippet alone.

For a review or coverage audit, give evidence locations, the operational consequence of each gap, and a concrete correction. Distinguish missing instrumentation from missing collection or queries. An explanation-only request needs a direct answer, not an audit.

The handoff names the signals or files changed, verification performed, and any remaining collection or alert-routing setup. Thresholds, sampling rates and retention choices need workload or operator justification; label illustrative values as examples.
