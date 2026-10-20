---
name: golang-documentation
description: 'Writes and reviews Go documentation grounded in current code. Use when creating or updating godoc or doc comments (package docs, doc.go, Deprecated notices), README, CONTRIBUTING, changelogs or release notes, installation or configuration guides, API docs, documentation sites, llms.txt, or executable Example functions. Not for naming/style refactors (golang-conventions), test strategy (golang-testing), API implementation, or release automation (golang-ci-release).'
---
# Go Documentation

Produce documentation that lets a library caller, application operator, or contributor use the current project without this conversation. Work in the project's existing documentation locations and conventions. For review-only requests, report discrepancies with evidence instead of editing. Documentation work changes documentation: report code defects, renames, signature changes, and missing tooling or infrastructure instead of making them, because the user asked for docs, not a refactor.

## Evidence before claims

Read the relevant implementation, tests, module paths, command definitions, configuration loading, and existing docs. Ground behavior, defaults, errors, ownership, concurrency guarantees, and installation paths in that evidence. Code establishes observable behavior; rationale, compatibility promises, and release plans need explicit project evidence. Surface conflicts between implementation and intended contracts rather than silently choosing a new contract.

Check supported Go versions against `go.mod`, workspace/toolchain settings, CI, and support policy. Keep examples, APIs, syntax, and commands compatible with the supported floor. Passing on an installed newer toolchain does not prove minimum-version compatibility; report conflicts or unavailable checks rather than raising the requirement.

When rewriting existing docs, keep every caller obligation, precondition, and breaking-change note the code still supports. Explain caller-relevant behavior without repeating signatures or inventing motivation. Optional sites, badges, demos, and AI indexes need an audience or request. Mixed library/application repositories may need both kinds of guidance.

## Focused references

- [Godoc](references/godoc.md): package and symbol comments, names, links, deprecation, and rendering.
- [Examples](references/examples.md): executable Example functions and runnable documentation snippets.
- [Project docs](references/project-docs.md): README, contribution and installation instructions, changelogs, sites, and `llms.txt`.
- [Application and API docs](references/application-api.md): CLI help, configuration, and service contracts.

## Verification and delivery

Run practical checks for the changed surface: scoped example tests, snippet compilation/execution, safe documented commands, `go doc`, or the repository's documentation build, link checker, and generator checks. Inspect command effects before execution; use temporary fixtures for commands that write data. Prefer existing pinned tools and avoid dependency or Go-version changes merely to check docs. Publishing, deployment, and external registration require their own user authorization.

Deliver the requested docs or review findings. In the final response, include exact check commands actually run, their results and toolchain, and any unverified claims with reasons. Distinguish static inspection, successful compilation, and executed behavior.
