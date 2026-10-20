# Connections and database context

## Pool ownership

Treat `*sql.DB`, `*sqlx.DB` and `*pgxpool.Pool` as long-lived shared pools, normally created at application startup and closed by their owner during shutdown. A borrowed repository pool is not closed per request. `sql.Open` need not establish a connection; use a bounded `PingContext` where startup requires connectivity. Native pgx pool construction and ping semantics depend on the installed API. A raw `*pgx.Conn` is one connection and is not a concurrency-safe pool.

Choose max-open connections against the server budget across all replicas and pools, reserving capacity for administration and other clients. Choose idle capacity and lifetime/idle expiry from workload and infrastructure limits, not copied constants. In `database/sql`, nonpositive max-open means unlimited; distinguish that from zero idle capacity. Configure pgxpool through its own settings rather than copying `sql.DB` setters.

Use `DB.Stats` or pgxpool statistics to separate saturation from leaks, slow queries and long transactions. Observe changes in cumulative wait count/duration alongside in-use, idle and server load. Increasing capacity can amplify database overload; find what holds connections first. Pool acquisition is part of a request's latency budget.

## Dedicated connections

Transactions and live rows pin connections. A `sql.Conn` obtained via `db.Conn(ctx)` must be closed to return it to the pool; a pgxpool acquired connection must be released. End rows and transactions before release, including error paths. Closing the pool is not a substitute for releasing borrowed resources.

Session state, temporary tables and session-level locks require explicit affinity and cleanup. Separate calls on a pool may use different sessions; leaked session settings can affect later borrowers. Prefer transaction-local settings where supported. Account for proxies that change session affinity.

## Deadlines and cancellation

Pass the caller context through connection acquisition, begin, queries and execution using `*Context` methods for `database/sql`/sqlx and context-taking native pgx methods. Bound optional query timeouts under the parent deadline and release their timers. A new background context in a request path discards the caller's cancellation and budget.

Keep query contexts alive until returned rows are consumed and closed. A helper that creates a timeout, defers cancel and returns live rows cancels the stream before its caller reads it. Either consume rows inside that helper or make the caller own the context and rows. `QueryRowContext` likewise needs a live context through `Scan`.

A deadline may expire waiting for a pool connection, waiting for a lock, executing SQL, or reading rows. Check both returned errors and iteration errors; drivers may surface cancellation through different error types. Preserve the underlying error and use `ctx.Err()` as supporting evidence, not a reason to mask unrelated errors. Cancellation support and server interruption vary by driver. Do not promise that a client timeout proves the server stopped immediately or that a write had no effect.

Coordinate client deadlines with engine-specific statement/lock timeouts when needed. Prefer scoped settings and ensure pooled sessions cannot leak a timeout to unrelated requests.
