# Transactions

Choose a transaction boundary from the invariant that must hold after success or failure. Related writes requiring all-or-nothing belong in one transaction; independent operations do not automatically need one. Arrange rollback immediately after a successful begin, perform every participating operation through the transaction handle, and report success only after a successful commit. A pool call inside a transaction executes outside that transaction and can also deadlock on pool exhaustion.

Keep the transaction short. Finish or close result sets before issuing another statement on its connection. Avoid external calls while holding locks. SQL rollback does not undo email, payment or queue side effects; retries require an idempotent external protocol or durable handoff such as an outbox. Repositories participating in one transaction must share that transaction rather than each starting their own. Savepoints are not independent commits; `database/sql` has no portable nested-transaction API.

## Isolation and contention

Derive isolation and locking from the anomaly to prevent, not from a label such as "financial". Defaults vary by engine and configuration; a nil transaction option does not universally mean READ COMMITTED. Verify supported levels and handle begin failures when the driver cannot honor them.

For a read-modify-write invariant, consider an atomic conditional update, optimistic version check, or a locking read in the same transaction. Use affected-row results under the driver's semantics to detect failed conditions. `SELECT ... FOR UPDATE` is engine-specific and locks selected existing rows; do not assume it protects missing rows or every predicate invariant. Constraints, range locks or serializable execution may be needed. SQLite has different locking/transaction modes and no PostgreSQL-style `FOR UPDATE`.

Acquire multiple row locks in a consistent order to reduce deadlocks. `NOWAIT` fails on contention; `SKIP LOCKED` omits locked rows and changes result semantics, which may suit a work queue but not a complete business read. Predicate visibility and phantom protection differ even between engines using the same isolation-level names.

## Failure and retry contract

Preserve the primary query or commit error when rollback also fails; retain useful cleanup diagnostics according to the project's error contract. Rollback after a completed transaction is expected to report a closed/done transaction and is not a new business failure.

Classify retryable errors by the actual driver's structured codes. PostgreSQL serialization failure (`40001`) and deadlock (`40P01`) can justify retrying the entire transaction in a fresh attempt, including all reads. Bound attempts and backoff by the caller's deadline; stop on cancellation. Replay is safe only if the complete operation's effects can be repeated. Do not retry every connection or commit error blindly.

A transport error during commit can leave the outcome unknown: the server may have committed before the client lost the response. Preserve that uncertainty and reconcile using durable operation identity or an idempotency mechanism before replay.

## Transaction context semantics

For `database/sql`, the `BeginTx` context governs the transaction until commit or rollback; cancellation causes the package to roll it back and commit returns an error. A short-lived helper context canceled as the helper returns must not own a transaction returned to a caller. `Commit`/`Rollback` themselves have no context parameter. sqlx follows these semantics through `database/sql`.

Native pgx `Begin`/`BeginTx` contexts cover the begin command, not automatic rollback of the transaction after later cancellation. Explicitly commit or roll back. If the request context is canceled, cleanup may need a separate short, bounded context so rollback can reach the server. Keep cleanup synchronous and owned, cancel that cleanup context, and handle unusable connections according to the pgx/pool contract; detached cleanup is not permission to continue business writes after cancellation.
