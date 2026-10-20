# Dependency risk

Produce a reasoned adoption or remediation decision, separating observed evidence from missing information. Popularity alone is not evidence of suitability.

## Adoption and footprint

Compare the standard library, existing project dependencies, and a small set of plausible alternatives against the actual requirement. Evaluate API fit, license obligations, upstream ownership and maintenance, release practices, supported Go versions, transitive dependencies and native/tooling requirements. Apply the repository's approved-dependency or license policy when one exists. State uncertainty when license or maintenance information is unavailable; do not invent a vetted-library list.

Distinguish a module being required, a package being imported, and code being linked into a deployed binary. `go mod why -m MODULE`, `go list -deps ./...`, and `go list -deps -test ./...` answer different questions. Tool/test dependencies still create development and supply-chain exposure even when absent from the binary. Measure the relevant built artifact before claiming binary-size impact; no entry in a size report does not prove a dependency is test-only.

## Dependency vulnerabilities

Use the project's configured scanner; for govulncheck, `govulncheck ./...` or a configured `go tool govulncheck ./...`. Include tests deliberately with `-test`. For a shipped artifact use supported binary mode, `govulncheck -mode=binary BINARY`, and explain its less precise reachability evidence. Scanner flags and supported Go versions should match the installed tool.

Record advisory ID, affected and fixed versions, selected module version, analysis configuration, and any reported vulnerable call path; read them from structured output (`govulncheck -format json`) rather than the text report. Source analysis can distinguish known vulnerable modules/packages from called vulnerable symbols; the level of reporting depends on scan settings and output format.

For vulnerability triage, give three evidence fields:

- **Module presence:** selected affected module/version, or what the supplied scanner finding establishes if versions are unavailable.
- **Analyzer reachability:** the reported path, or no path reported under the stated scan configuration (build tags, platforms, `-test`, source or binary mode, advisory coverage). A reported path is static evidence, not proof of exploitability.
- **Runtime exploitability:** demonstrated attack prerequisites, or not established. A missing static path alone does not settle this field.

For dependency-only remediation, select a compatible fixed version, inspect transitive changes and verify the affected code. If the remedy changes trust-boundary defenses in application code, identify that security-review work explicitly.

Report unresolved vulnerabilities, unavailable scans and acceptance decisions honestly; merging updates and suppressing advisories stay the user's decisions.
