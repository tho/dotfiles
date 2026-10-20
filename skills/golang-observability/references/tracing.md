# Distributed tracing

Own OpenTelemetry SDK configuration at the application boundary; reusable packages accept or obtain instrumentation without installing global providers. Reuse the existing tracer provider where present. A provider alone does not establish cross-service propagation.

## Lifecycle and propagation

Configure an exporter, service resource identity, batching, sampling and the propagator expected by peers, commonly W3C TraceContext. Propagate baggage only under an explicit data policy; inbound baggage is untrusted. Pass the context returned by span creation, never context.Background, to child calls and context-aware database operations. Extract incoming carrier context and inject outgoing HTTP or messaging context using compatible instrumentation.

For asynchronous messages, choose parentage or span links consistent with the messaging operation and preserve the appropriate carrier. Do not invent a request parent for unrelated background work.

Flush and shut down the provider using a fresh bounded context during application shutdown; an already canceled request or process context can discard buffered spans. Handle shutdown errors and initialization failures according to the service's telemetry policy.

## Span content and cost

Instrument service boundaries and meaningful operations. Use stable span names and normalized route templates. Attribute cardinality and payload volume still cost storage.

RecordError adds an error event; it does not set span status. For a failed operation that warrants error status, record the sanitized error and set codes.Error with a safe description. Respect the instrumentation's semantic conventions for HTTP status and expected cancellation; an ordinary client error is not necessarily a server span failure.

Use parent-based sampling with an explicit root policy to keep service sampling decisions coherent. Head sampling cannot guarantee retention of later failures. Tail sampling needs collector capacity and routing that lets the sampler see a trace's spans; it cannot recover spans dropped by upstream head sampling. Set batch limits and timeouts, and expose exporter drops or failures without recursively tracing export traffic.

Verify parent-child relationships across a real carrier boundary with a recording exporter or collector. Check span end, status, sanitized attributes and shutdown. Confirm logs refer to the active span and distinguish valid trace context from a sampled, stored trace.
