# Godoc

Write comments against the actual declaration and implementation. Start a declaration's summary with its exact exported name. Use `Package name ...` for importable package summaries; describe a command as a command for `package main`.

Use actual package names, import paths, capitalization, and initialisms in prose and snippets. Read the declaration instead of deriving its name from the directory. Show qualified names as callers see them; leave stutter to a separate rename.

Document caller-relevant contracts: useful zero values, valid inputs, returned errors and how callers recognize them, mutation and ownership, resource lifetime, cancellation, and concurrency guarantees where applicable. Include only guarantees supported by code or an explicit contract. An interface contract describes obligations on implementers; a concrete implementation's behavior does not automatically become a promise for every implementation.

Use Go doc-comment syntax, not arbitrary Markdown: paragraphs, indented code, supported headings, and resolvable symbol links such as `[Type]` and `[Type.Method]`. Check formatting support against the project toolchain. Plain URL links and explicit link definitions serve external references. Inspect `go doc` output; terminal output is not a browser-rendering check. Use an existing local documentation renderer when rendering matters.

Put `Deprecated:` at the beginning of its own paragraph and name the verified replacement or migration guidance. Include removal versions or dates only when the project has committed to them. Preserve documented compatibility constraints and distinguish an existing bug from a promised behavior.

A prose-only example is not an executable test. Use real, verified Playground URLs only for public code when sharing is requested; a fabricated URL or placeholder must not appear as a working demo. Local documentation is appropriate for private modules; public pkg.go.dev indexing is not guaranteed by a local build or tag.
