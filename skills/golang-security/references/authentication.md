# Authentication, authorization, and browser sessions

Authenticate the caller and authorize the requested action on the specific resource and tenant. A valid token, private network, or proxy header alone does not establish object-level permission. Proxy-supplied identity is untrusted until the proxy boundary is verified; the network reference owns forwarded-header trust.

## Tokens and sessions

- Pin permitted JWT signing algorithms and trusted keys, validate signature, issuer, audience, required expiration, and applicable time claims. For an RS256-only contract, accepting every RSA algorithm is too broad. An unverified `kid` or key URL must not select arbitrary files or network destinations.
- Generate session tokens with `crypto/rand`; seeding `math/rand` from a secure source does not make its output suitable for secrets. Rotate session identifiers after authentication and privilege changes, and implement expiration and logout invalidation according to the session design.
- Protect shared session state and keep permission checks consistent with the intended update/revocation semantics.
- Validate loaded signing and encryption keys for required presence, encoding, and size. A signed client-side session is readable unless also encrypted; use encryption when its contents require confidentiality. Keep server-side authorization current even when the cookie contains a role.

## Cookies and CSRF

Use `Secure` for cookies sent over HTTPS and `HttpOnly` for authentication cookies. A separate CSRF cookie deliberately read by JavaScript stays readable; preserve the chosen token transport instead of forcing one flag onto every cookie. Prefer host-only cookies by omitting `Domain`. Setting a Domain attribute includes its subdomains; a subdomain-valued Domain is still not host-only. The `__Host-` prefix requires Secure, Path `/`, and no Domain, but does not create a port-scoped origin boundary.

Protect cookie-authenticated state changes with a CSRF token bound to the session, a correctly signed session-bound double-submit design, or a strict origin-validation strategy suited to the clients. Reject missing or invalid proof according to an explicit policy; do not fail open when a header is absent. Compare full origins against trusted configuration, not a suffix or attacker-supplied Host value. Keep GET and other safe methods free of state changes.

SameSite is defense in depth: same-site is broader than same-origin, and sibling subdomains may be hostile. Use Lax or Strict where compatible; intentional cross-site cookies need SameSite=None and Secure plus the appropriate CSRF defense. CORS alone is not a general CSRF defense because it primarily controls response access and some cross-origin requests can still be sent.

Test valid requests, foreign-origin requests, absent or malformed proof, and the application's required cross-site flows.
