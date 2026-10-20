# Secrets and information disclosure

Trace sensitive data through responses, error strings, logs, traces, metrics, crash reports, and third-party hooks. Authorization to process data does not automatically authorize every downstream destination to receive it.

- Load credentials from the deployment's approved secret source, such as a secret manager, protected file, or environment. Validate required values without printing them. Environment variables are a delivery mechanism, not a guarantee against process inspection, diagnostic dumps, or accidental logging.
- If a live credential was committed or exposed, removal alone does not revoke it. Recommend rotation or revocation and assess copies in history and downstream systems. Keep example placeholders distinct from verified live secrets.
- Public error responses need a deliberately safe representation. `%v` can leak the same text as `%w`; removing unwrap support does not sanitize a message. Conversely, an internal error chain is not directly exposed to an HTTP client merely because Go callers can use `errors.As`.
- Keep useful internal diagnostics at the responsible boundary, but redact secrets there too. Do not unconditionally log raw database errors, DSNs, request bodies, headers, or entire user structs.

## Logging and telemetry

Select permitted fields rather than serializing objects and hoping a denylist catches everything. Apply data minimization and retention/access policies to identifiers and IP addresses as well as obvious personal fields.

Prevent forged log records according to the actual encoder and downstream parser. Standard JSON encoding escapes newline characters in string values; custom handlers or later decoding may change that. For line-oriented text sinks, escape or reject line breaks and relevant control characters rather than preserving them in a purported sanitizer.

Check redaction across nested attributes, breadcrumbs, exception text, URLs, query strings, headers with varying case, and SDK defaults. A top-level hook deleting two headers is not proof the event is clean. Verify the emitted payload before it leaves the process using representative sensitive data.

An internal user ID or hashed email can remain personal or linkable data. An unsalted email hash is dictionary-searchable; truncation also increases collisions. Where correlation is justified, use an appropriately scoped pseudonymous identifier or keyed derivation, and retain the applicable privacy controls. Do not claim anonymization or regulatory compliance from hashing alone.
