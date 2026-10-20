# Structured logging

Use the project's structured logger. For new Go 1.21+ code, log/slog is a standard-library default. A requested migration from zap, logrus or zerolog should preserve field names, levels, destinations and redaction before removing the old backend. Bridge incrementally where needed, and check for duplicate delivery.

## Correlation and ownership

The slog Context methods pass context to a handler; the standard JSONHandler does not extract trace_id or span_id. Add valid IDs from the active OpenTelemetry SpanContext explicitly or use a handler that extracts them. Test the serialized record, including requests without a valid span. The otelslog bridge creates OpenTelemetry log records and requires an SDK LoggerProvider and export pipeline; it does not automatically enrich a separate stdout JSON handler.

Create request-scoped child loggers rather than mutating the global logger per request. Treat incoming request IDs as untrusted: validate and bound them or generate your own. Keep trace IDs distinct from arbitrary request IDs.

Log a terminal error at the boundary that handles it; intermediate layers generally wrap and return it. Recording an error on a span is a separate signal, not a reason to duplicate error logs. Expected cancellations and client mistakes need levels appropriate to their operational impact.

## Volume and data

Guard expensive attribute construction with Enabled when it would otherwise run at disabled levels.

Redact before emission, including error strings, nested attributes, database arguments and URLs containing query tokens. Bound external strings; preserve required audit events when sampling repetitive diagnostics. Define sink failure and flush behavior for buffered handlers.

Verify representative records for field types, level filtering, redaction, correlation and one terminal log per failure. During migration, compare records against the existing collector schema and alerts.
