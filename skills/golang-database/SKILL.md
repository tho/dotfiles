---
name: golang-database
description: 'Guides Go SQL database access. Use when writing, reviewing or debugging database/sql, sqlx or pgx code against PostgreSQL, MySQL/MariaDB or SQLite: queries, row scanning, transactions, isolation, connection pools, batches or database-operation cancellation. Not for schema or migration SQL design, general security audits, goroutine coordination, or general context architecture.'
---

# Go Database

Produce Go database code, or review findings, that a maintainer can use with confidence about query results, atomicity, cancellation and connection ownership. Ground decisions in the project's driver, database engine/version, schema, repository patterns and supported Go version. Preserve the existing stack; prefer explicit SQL for new access code without imposing a library migration.

## Database contract

Establish the operation's result and failure contract: missing rows, NULL versus zero values, affected-row expectations, atomicity across statements, and ownership of rows, transactions and connections. Use the actual engine's isolation and locking semantics; PostgreSQL, MySQL/MariaDB and SQLite are not interchangeable.

Bind values using the driver's placeholders; choose dynamic identifiers from trusted SQL fragments.

Work with the existing schema and migration tooling; identify missing schema guarantees or index evidence without silently changing DDL. Existing triggers, views or row-level policies are part of the database contract to inspect, not features to remove automatically.

## Focused references

Read the references relevant to the requested operation:

- [Queries and results](references/queries.md): method choice, scanning, missing rows, NULLs, batches and pagination.
- [Transactions](references/transactions.md): atomicity, isolation, locking, retry decisions, commit outcomes, and transaction context and cleanup.
- [Connections and context](references/connections-context.md): pool lifecycle, acquisition, session affinity and streaming deadlines.

## Evidence and delivery

Verify the affected contract at the appropriate boundary. Mocks can check arguments, cleanup and error paths; real-engine tests are needed for SQL validity, NULL round trips, constraints, isolation, locking and cancellation behavior. Use the project's test conventions and a disposable database. Cancellation tests should check eventual connection release as well as the returned error; atomicity tests should check persisted state after failure.

For reviews, tie findings to concrete code paths and consequences. For changes, report what changed, checks actually run, and any unverified engine/driver assumptions. Base throughput claims on production-like data volumes, not toy fixtures.
