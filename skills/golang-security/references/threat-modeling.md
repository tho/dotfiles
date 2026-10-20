# Threat modeling and risk evidence

Produce a threat model that lets a maintainer choose and verify controls. Name assets, actors, entry points, data flows, trust boundaries, deployment assumptions, and the capabilities of a compromised component.

Use STRIDE as a coverage aid across the relevant flows:

| Threat | Concrete question |
| --- | --- |
| Spoofing | Can a caller forge identity, a proxy assertion, or a webhook sender? |
| Tampering | Can payloads, stored objects, or authenticated metadata be changed undetected, or a signed webhook or queued job be replayed to repeat its effect? Signature, freshness, and idempotency are separate properties (cryptography reference). |
| Repudiation | Is there sufficient protected evidence of consequential actions? |
| Information disclosure | Can responses, outbound fetches, logs, or telemetry expose protected data? |
| Denial of service | Can hostile input exhaust bounded resources or bypass quotas? |
| Elevation of privilege | Can an authenticated actor cross object, tenant, or administrative boundaries? |

For each threat, record existing controls, possible bypasses supported by evidence, residual impact, and a mitigation with an observable verification condition. A hypothetical future removal of a working control is not evidence that the present system is exploitable.

If the team uses DREAD, document the assumptions behind Damage, Reproducibility, Exploitability, Affected users, and Discoverability scores. Their average is a prioritization convention, not an objective measurement or a substitute for evidence.
