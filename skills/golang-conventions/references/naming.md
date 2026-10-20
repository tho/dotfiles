# Naming details

Choose names that communicate intent at actual Go call sites. Existing repository conventions and compatibility requirements outrank the defaults here.

## Names by role

| Concern | Default and reason |
| --- | --- |
| Packages | Short lowercase names describing purpose: `json`, `auth`, `tabwriter`. Avoid vague buckets such as `util` or `common`. Numbers are valid, as in `oauth2`. |
| Files and directories | Lowercase files with underscores between words, such as `user_handler.go`. Preserve meaningful `_test.go`, OS and architecture suffixes. Match package and directory names when practical; preserve established layouts. |
| Identifier casing | MixedCaps, with exported names capitalized. Keep initialisms intact: `URL`, `userID`, `HTTPServer`, `xmlParser`. Underscores are reasonable in test subcases, generated code and interop; `http_test` is a valid external test package. |
| Variables and parameters | Name the domain concept, not the storage type: `users`, not `userSlice`. Match name length to scope. Use `ctx`, `err`, `i`, `n`, `r`, `w` where their meaning is clear; distinguish ambiguous values such as `sec` and `nsec`. |
| Receivers | A short type-derived name, usually one or two letters, consistent across methods. `s *Server` is clearer than switching between `self`, `this` and `srv`. |
| Structs and constants | Nouns for entities; role-based constants such as `DefaultPort`, not `Port8080`. Avoid empty suffixes such as `Struct` or `Object`. |
| Constructors | `New` for a single primary constructible type; qualify multiple constructors when needed, as in `http.NewRequest`. Judge stuttering at the package-qualified call site. |
| Accessors and actions | `Name` and `SetName` for field access, verbs for actions. Keep meaningful `Get`, as in HTTP GET. `Fetch` or `Compute` can signal substantial work. |
| Predicates | Names should read as questions: `IsReady`, `HasPrefix`, `CanRetry`. Existing clear predicates such as `Empty` remain valid. |
| Interface names | A recognizable capability such as `Reader`, or a descriptive/composed name such as `ReadWriteCloser`. Preserve canonical signatures when implementing standard interfaces; a method's spelling alone does not establish conformance. |
| Options | `WithPort`, `WithLogger`; remove redundant context from types, as in `server.Option` and `server.Options`. Qualify options for multiple distinct APIs only when useful. |
| Variants | `f` for formatting functions; `Must` for panic-on-error variants; `Context` or `WithContext` where an existing API needs a context variant. New APIs can accept context directly. |
| Errors | `ErrNotFound` for sentinel variables and `PathError` for types. Start ordinary error prose lowercase and omit terminal punctuation so wrapping reads naturally. Preserve meaningful acronym/proper-name casing. Package prefixes may clarify sentinel origins but need not duplicate existing context. |
| Enums | Type-prefixed values where needed for clarity. Reserve `Unknown`/`Invalid` at zero, or skip zero, when an uninitialized value must be distinguished. A deliberately useful zero value is also valid. |
| Tests | `TestParseToken`, `TestServer_Handle`, descriptive subtest phrases, and clear `input`/`expected` or established `got`/`want` names. `mustLoadFixture` signals a helper that cannot return normally on failure. |

## Context and exceptions

Use the same domain term consistently, without banning locally clear abbreviations. Avoid stuttering beyond the main type: `dbpool.Status` and `dbpool.Option` usually read better than `dbpool.PoolStatus` and `dbpool.PoolOption`.

Alias imports to resolve actual package-name collisions or honor an established generated-code convention such as `pb`. Check the declared package name; the final import-path segment is not proof of its name. Preserve special directory semantics: `internal` restricts imports by the parent tree; `testdata` is ignored during package discovery; `vendor` has dependency semantics; `cmd` is a convention for executables.

Some style guides prefer singular package names, prefixed boolean fields, lowercase acronyms in error/subtest prose, and `In` for in-place variants. These are optional repository policies, not Go requirements. Do not mechanically rename valid plural packages, `ready bool`, `invalid URL`, or an established mutating API. Explain mutation through an established name and API documentation when no local suffix convention exists.

Renaming exported names requires examining downstream callers and interfaces; review recommendations should make any migration cost explicit. When a rename is worth it, keep the old name as a deprecated alias or wrapper for a transition period so callers can migrate without breaking.
