# Errors

An error contract defines which failures callers can inspect, what context survives propagation, and who handles the final failure.

## Values and contracts

- Check failures before using results unless the API explicitly permits partial results. An intentionally ignored error needs a reason grounded in the operation's contract, such as a write to a buffer that cannot fail.
- Use a package sentinel when callers need a stable condition, a custom error type when they need fields, and a contextual error when only a description is needed. Implement Unwrap on a custom wrapper if its cause is part of the contract.
- Add context where it explains an operation or boundary; do not wrap mechanically at every function. Use `%w` to preserve a cause that callers should inspect.
- Go 1.26 adds errors.AsType[T] for targets implementing error. For earlier versions, or interface targets that do not implement error, use errors.As with a pointer to the target variable.
- Decide whether a public API exposes its underlying cause. Replacing `%w` with `%v` breaks unwrapping but still includes the original text. It does not sanitize secrets or make an error safe for a user response. Translate to a public condition or message when needed.

## Multiple failures

Use errors.Join (Go 1.20+) when independent failures should survive together, such as validation findings or a primary operation plus cleanup failures. It ignores nil arguments and returns nil when all are nil. Both errors.Is and errors.As traverse joined errors; errors.Unwrap alone does not traverse a multi-error tree.

## Handling and logging ownership

Propagate errors from lower layers to the boundary responsible for deciding the outcome. Avoid logging the same terminal failure at each returning layer. A retry log may describe an intermediate failed attempt without duplicating the terminal error log.

At the logging boundary, use the project's structured logger, or log/slog on Go 1.21+ if a logger must be chosen. Keep the event message stable and put IDs, paths, counts, and durations in fields. Exclude secrets and sensitive payloads from both the message and the fields.

Keep detailed internal diagnostics separate from public responses.

## Panic and recovery

Return errors for expected failures. Panic can express a violated programming invariant or an explicitly documented Must-style API.

Recover only at a boundary that can safely abandon or isolate the failed operation. Recovery runs in a deferred function in the same goroutine as the panic; a parent goroutine cannot recover a child's panic. Preserve diagnostic context and a stack trace, and expose a failure outcome rather than silently continuing with partial state. Some runtime fatal errors cannot be recovered.

For HTTP recovery, account for responses that have already committed headers or body bytes; writing a fresh error response at that point cannot replace the earlier response.
