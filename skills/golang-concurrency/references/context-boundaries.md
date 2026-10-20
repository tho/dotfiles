# Context across API boundaries

Pass ctx context.Context as the first argument to operations. Prefer per-call parameters to request contexts stored in long-lived service structs, which can reuse canceled or unrelated lifetimes. A type whose explicit contract owns a lifetime is a different case; make that ownership clear rather than mechanically banning every context field.

Make context ancestry explicit, including in migration plans: an owned process lifetime starts from context.Background(), for example through signal.NotifyContext(context.Background(), os.Interrupt) in main with its returned stop function released by the owner. HTTP request work starts from r.Context(); derived operation contexts retain that ancestry. Use context.TODO() only for an acknowledged migration gap where no caller context is available yet. TODO has no cancellation or deadline, so mark and close that gap. Do not pass nil contexts.

## HTTP and database operations

Incoming HTTP request cancellation can occur on connection closure, HTTP/2 cancellation, or handler return. Client disconnection is not a durable execution boundary.

Use http.NewRequestWithContext for outgoing calls. Coordinate request deadlines with client/transport timeouts, close response bodies on owned paths, and keep the attempt context alive until its body has been consumed or handed off with explicit cleanup ownership. Canceling a request immediately after receiving headers can interrupt body reading. Retries need a total budget, cancellation-aware backoff, and cleanup scoped to each attempt rather than defers accumulating across the loop.

With database/sql, propagate context through BeginTx, QueryContext, QueryRowContext, and ExecContext, including transaction methods. The BeginTx context remains relevant through the transaction; cancellation causes database/sql to roll it back. Driver support affects interruption of in-flight work. sql.Tx has Commit and Rollback, not CommitContext or RollbackContext. A timeout does not by itself establish whether an external side effect committed.

## Values and tracing

Use context values for request-scoped metadata crossing API boundaries, not for hiding required arguments, configuration, or service dependencies. Use package-private comparable key types and typed accessors that handle absence. Authenticated identity metadata may belong in context; an order's target user ID can still be an explicit business argument.

Infrastructure loggers belong in explicit dependencies; a request-enriched logger can be context metadata if that is the project's convention. Context's own concurrent safety does not make mutable stored values safe.

Across services, inject and extract selected metadata with the project's tracing propagator or documented header contract. Do not serialize a context or assume cancellation automatically crosses a network boundary. With OpenTelemetry, use the configured instrumentation and propagators; do not invent independent span IDs or trust incoming identity headers as authentication.
