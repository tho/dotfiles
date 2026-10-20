---
name: golang-security
description: 'Finds and fixes security weaknesses in Go code. Use when auditing, security-reviewing or hardening Go code, threat modeling trust boundaries, or preventing SQL or command injection, XSS, SSRF, path traversal and archive extraction, authorization bypass and IDOR, JWT, session cookie and CSRF flaws, weak password hashing, encryption or TLS misuse, leaked secrets or credentials, or hostile-input resource exhaustion. Not for ordinary correctness bugs (golang-correctness), concurrency design (golang-concurrency), dependency-only govulncheck CVE scans (golang-dependencies), CI scanner wiring (golang-ci-release), or routine logging and telemetry volume (golang-observability).'
---

# Go Security

Help Go developers protect assets across trust boundaries. Produce code or findings a maintainer can act on: attacker control, reachable behavior, existing defenses, impact, and verification are explicit.

Use the project's declared Go version and deployment model.

## Security bar

- Trace untrusted data through existing controls to the sensitive operation. Inspect adjacent code to establish reachability while keeping diff findings relevant to the change.
- Separate demonstrated vulnerabilities, unresolved assumptions, and optional hardening. Enforced upstream constraints can eliminate an attack. Base severity on impact and prerequisites, not API names.
- Fail closed when required security controls fail. Include overflow, aliasing, or races in findings only with an explained security consequence.
- Give every cookie-authenticated state change a CSRF verdict, even when the task does not mention CSRF.

## Focused references

Read only the references relevant to the task. Paths are relative to this skill's directory.

| Concern | Reference |
| --- | --- |
| SQL, command arguments, templates, XSS, and decoding | [Injection](references/injection.md) |
| Root confinement, symlinks, archives, and permissions | [Filesystem](references/filesystem.md) |
| SSRF, redirects, TLS, debug endpoints, and resource exhaustion | [Network](references/network.md) |
| Authorization, JWT, sessions, cookies, and CSRF | [Authentication](references/authentication.md) |
| Randomness, passwords, encryption, key rotation, HMAC, and signed messages | [Cryptography](references/cryptography.md) |
| Secrets, error disclosure, logging, and third-party telemetry | [Data exposure](references/data-exposure.md) |
| Trust boundaries, STRIDE, and risk prioritization | [Threat modeling](references/threat-modeling.md) |

## Evidence and handoff

For review, give each finding a location, attack prerequisites, reachable failure, impact, existing defenses, and correction. Mark missing evidence as uncertainty. A review alone is read-only: report findings without editing code, adding suppression comments, installing scanners, or changing dependencies.

For implementation, verify the boundary with abuse cases and valid-use cases. Use available analysis, fuzzing, or race checks when they test the claim; a clean scan does not prove security. Report checks, results, and unverified assumptions.
