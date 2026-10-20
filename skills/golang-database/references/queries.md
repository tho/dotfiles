# Queries and results

Match the API to the result: `INSERT ... RETURNING` returns rows, so it needs a query method rather than `ExecContext`. `QueryRowContext` defers query errors to `Scan` and does not validate that at most one row matched; use schema guarantees or explicit cardinality checks where that matters.

Bind values separately from SQL text using the driver's dialect (`$1` for PostgreSQL, commonly `?` for MySQL). Placeholders do not substitute identifiers or a whole list. For sqlx lists, define empty-list behavior first, then `sqlx.In`, then `Rebind`; propagate expansion errors. Supported array parameters are another PostgreSQL option. Map dynamic identifiers and sort directions to trusted fixed fragments.

## Scanning and ownership

Select explicit columns and match scan order and types. sqlx uses `db` tags; pgx v5 offers `CollectRows` with `RowToStructByName`, subject to the installed version's matching rules. Check library APIs against the version in `go.mod` rather than assuming examples from another major version apply.

Keep NULL distinct from a meaningful zero. Use pointer destinations supported by the driver, `sql.Null*`, Go-version-compatible `sql.Null[T]`, or pgx nullable types. `COALESCE` is appropriate only when collapsing the distinction is the intended contract. Nullable wrappers need deliberate JSON mapping; their default encoding is not necessarily a scalar or null.

After a successful streaming query, arrange immediate `rows.Close()` on every exit, check every `Scan`, and check `rows.Err()` after iteration. Handle any close error relevant to the operation without replacing an earlier primary failure. Collect helpers may own closure; verify that contract.

Distinguish `sql.ErrNoRows` or the installed pgx equivalent from operational errors, preserving error identity for callers. A multi-row query returning no rows is normally an empty result, not `ErrNoRows`. Detect constraint failures with driver codes and, where needed, constraint identity rather than matching message text. Interpret `RowsAffected` under the engine/driver configuration: MySQL matched-versus-changed counts differ. Check result errors; do not assume every driver supports `LastInsertId`.

## Batches and pagination

Choose batch size from parameter limits, payload size, memory, lock duration and deadline budget. Define whether failure may leave earlier batches committed; use a transaction when the contract requires all-or-nothing. Keep buffers bounded for large streams. PostgreSQL `CopyFrom` and pgx batches can reduce round trips, but verify their transaction semantics and consume/check/close batch results before reusing the connection.

Use a deterministic total order for pagination. A non-unique timestamp cursor needs a stable tie-breaker such as `(created_at, id)` in both predicate and ordering; define NULL handling and changes between pages. Keyset pagination can avoid deep OFFSET work when supported by the query and indexes, but is not an unconditional complexity guarantee.

For N+1 or slow-query work, inspect actual queries and plans before choosing joins, batching or index proposals. `EXPLAIN ANALYZE` executes the statement and may cause writes or expensive load. Use a suitable test environment and inspect plain `EXPLAIN` first when execution is inappropriate. Propose index changes rather than applying them.
