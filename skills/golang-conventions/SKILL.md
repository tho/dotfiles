---
name: golang-conventions
description: 'Guides Go naming and code clarity. Use when answering naming or style questions, even about a single identifier or expression; choosing package, identifier or API names; reviewing Go style; simplifying control flow; or establishing Go conventions. Not for linter configuration, documentation writing, test strategy, correctness debugging, concurrency design or performance analysis.'
---

# Go Conventions

Help maintainers read Go code without reconstructing its intent. Produce names and style changes that fit the repository, or review findings on confusing code.

Repository conventions and explicit user requirements take precedence over these community defaults. Preserve behavior and public compatibility during style edits; a clearer name alone does not authorize breaking callers. Distinguish a correctness defect from a discretionary style preference.

## Core conventions

- Read names at their call sites: `user.New`, `http.Client`, and `config.Parse` avoid repeating package context. Use one term per domain concept, with shorter local names where the scope makes the meaning obvious.
- Use MixedCaps identifiers and consistent initialisms (`userID`, `HTTPServer`, `xmlParser`). Constants describe roles rather than literal values. Keep receiver names short and consistent across a type's methods.
- Prefer focused functions, early handling of errors and edge cases, and a minimally indented happy path. Remove `else` after terminating branches. Name complicated conditions without eagerly evaluating checks that depend on short-circuiting.
- Let declarations reveal intent: `var` for useful zero values, `:=` for computed or nonzero values, keyed struct literals for readable construction. Choose nil versus empty collections according to the API contract.
- Break long expressions at semantic boundaries. Treat roughly 120 columns, four call arguments, and four function parameters as prompts to inspect readability, not mechanical limits. Group parameters only when they form a coherent concept.
- Keep public surface intentional. Organize related declarations together and prefer straightforward standard-library operations over speculative abstractions or new dependencies.

## Details by concern

Read [naming](references/naming.md) for package and file names, constructors, predicates, options, interfaces, errors, enum names, tests, and optional style-guide preferences that need repository agreement.

Read [clarity](references/clarity.md) for line breaks, declarations, condition extraction, function signatures, pointer arguments, file organization, string handling, and behavior risks of style edits. Load both for a combined conventions review.

## Applying conventions

In a review, prioritize confusing call sites and behavior-sensitive rewrites over cosmetic uniformity. Give the location, proposed change, and reason; acknowledge a valid repository convention instead of reporting it as a violation. Explain a deliberate exception when its reason would otherwise be lost, without adding comments that merely narrate syntax.

For edits, inspect callers and interfaces before changing exported names. Use a semantic rename tool when available, then verify references and affected behavior; do not assume a rename tool guarantees API compatibility. Keep formatting enforcement in the repository's existing formatter and linter workflow. Validate changed Go code with focused checks appropriate to the change.
