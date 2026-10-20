# Network trust boundaries

## SSRF and redirects

An outbound URL check must constrain the destination actually contacted, not only its textual hostname.

- Parse and validate errors, schemes, authority, ports, and userinfo against the intended service policy. Prefer an explicit destination allowlist when the feature permits it.
- For arbitrary public-URL fetches, reject forbidden address ranges, including loopback, private, link-local, unspecified, and relevant IPv6 or IPv4-mapped addresses. Include cloud metadata destinations. A substring check for `metadata` or a private IPv4 list alone is insufficient.
- Bind DNS validation to dialing: validate resolved addresses and connect only to an approved address while preserving the original host for TLS verification and HTTP routing. Resolving again after checking permits DNS rebinding.
- Reapply destination policy at each redirect or disable redirects. Account for proxies and alternate transports that could bypass the checked dial path. Limit redirects, time, and response bytes.
- For browser redirects, allow only intended hosts or well-defined local paths. A leading slash alone permits scheme-relative `//host` URLs. Validate parsed authority and scheme and account for browser interpretation of backslashes.

## Transport and exposure

Verify TLS certificates and names, and prefer library defaults over stale cipher lists. Trust a development CA through a certificate pool instead of disabling verification. Check CA parsing succeeds. For mTLS, client certificates and client-side `RootCAs` do not configure server-side client authentication; the server also needs the intended client CA and verification policy.

Verify SSH host keys using pinned keys or a managed known-hosts policy. Unknown or changed keys require an explicit trust decision.

Assess listener and debug endpoint reachability in the deployment. Binding to all interfaces is not automatically a vulnerability, and loopback is not an authorization boundary against local attackers. Keep pprof and administrative endpoints on a separately controlled listener or behind appropriate access controls. Inspect the actual mux rather than assuming a pprof import exposes every server.

## Resource exhaustion and browser policy

Set header, body, idle, and operation deadlines appropriate to the protocol. `ReadHeaderTimeout` protects header parsing; streaming responses may need per-operation deadlines rather than a blanket write timeout. Bound request and response bodies, expensive computations, queues, and per-client state; the injection reference owns decoded-size limits.

Rate limit using an identity whose trust is established. Trust forwarded addresses only from configured proxies that replace untrusted headers. Bound and expire the limiter registry so unique identities cannot exhaust memory. Authentication controls may need both account and source limits.

Choose CSP, framing, content-type, referrer, and permissions policies for the actual browser application. Prefer CSP nonces or hashes for required inline scripts. Apply HSTS where HTTPS is served, and enable `includeSubDomains` only when all affected subdomains support it. Headers supplement application controls; missing one is not automatically an exploitable finding.
