# HTTP and integration tests

Test the boundary the caller depends on.

## HTTP

Use `httptest.NewRecorder` and a request to exercise a handler directly. Assert meaningful status, headers, and response semantics, including malformed input and relevant authentication/error paths. Guard decoding with `require.NoError` before checking fields. Use `JSONEq` for semantic JSON comparison when decoding into a type adds no value.

Use `httptest.NewServer` when the contract involves client behavior, middleware wiring, redirects, or real HTTP transport. Register server cleanup and close response bodies. Give client operations bounded contexts or timeouts so a broken implementation cannot hang the suite. Handler-only tests do not establish transport behavior.

## External dependencies

Follow the repository's integration-test selection convention; use an `integration` build tag when a separate opt-in lane is needed. Document the command that actually includes those tests, such as `go test -tags=integration ./...`. A command without the required tag is not evidence that integration tests passed.

Fixtures need explicit ownership and isolation:

- Register cleanup immediately after successfully acquiring a resource so later setup failures still release it. Cleanup only resources owned by the test run.
- Wait for readiness with a bounded health check or `PingContext`, not a fixed sleep. `sql.Open` alone does not establish a database connection.
- Give concurrent runs independent schemas, databases, or other namespaces. Fixed ports and shared truncation can collide across runs even if tests are sequential within one process.
- Set the isolated namespace on parsed connection configuration and reconcile conflicting settings; changing a URL path alone can leave a `dbname` query override active. Supply the resulting configuration to every application pool, and verify its effective database/schema before resetting fixtures so a configuration mistake cannot modify shared data.
- A rollback isolates writes only if the code under test uses that transaction. Background workers and separate connections require a different isolation strategy.
- Check fixture read and initialization errors. Use fresh mutable data per test; choose fixed timestamps and identifiers unless variability is part of the case.
- Mark missing services as skipped only when the test lane permits skipping. An explicitly required integration lane should fail with a useful setup error instead of reporting a misleading green run.
