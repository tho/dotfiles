# Semantic tooling and bounded rewrites

Use the project's available Go toolchain and semantic tools. Check tool versions and installed help before choosing an action; unsupported commands should not turn into guessed invocations.

## gopls

Map declarations and references through the editor/LSP interface or gopls CLI. Inspect package imports with Go tooling as well as references; textual search supplements this for tags, templates and reflection strings.

Check the installed rename help for preview/write behavior and use the preview before enabling writes. Discover supported code actions for the selected source range before invoking Extract or Inline; action identifiers and command syntax vary with gopls versions. If a rename is refused, examine shadowing, method sets and interface satisfaction before attempting a smaller manual edit.

For missing gopls, explain the limitation, use available type-aware editor tooling if present, or propose a toolchain-compatible gopls version. A scoped manual change with explicit reference and test coverage is a fallback, not an equivalent safety guarantee. Do not silently install an unpinned latest tool or claim semantic verification from text search.

## Bulk transforms

| Tool | Appropriate scope and limitation |
| --- | --- |
| gofmt rewrite | Expression-shaped syntactic replacements; cannot distinguish look-alike symbols by type. Preview selected files, not the whole tree by default. |
| eg | Type-aware expression rewrites using before/after templates. Check side-effect duplication and its support for the project's language version. |
| gopatch | Statement-level migration patterns. Preview first and review unmatched cases and import changes. |
| go/analysis SuggestedFixes | Repeated domain-specific changes needing type information. Test the fixer on positive, negative and side-effect cases before broad application. |
| Decorated syntax tree tooling | Bespoke edits where comments and formatting must survive movement. Preserve directives as well as ordinary comments. |
| go fix / modernize analyzers | Version-driven fixes; the available fixers depend on the installed version. Review the resulting semantics and Go floor rather than assuming every enabled fixer is acceptable. |

Prefer the smallest tool that matches the actual symbols and preserves evaluation semantics. A regex cannot distinguish code from strings, comments or unrelated identifiers. Repeated hand editing is also error-prone; a tested rewrite is justified when repetition makes it safer.

Format and resolve imports only for affected files; import cleanup is not authorization to reorder dependency versions. Dead-code analysis is a hint: reflection, assembly, linkname, plugins and external consumers can invalidate a reachability conclusion, especially for exported libraries.
