# Kong

Use Kong for a CLI whose commands, arguments, and flags benefit from a typed struct model. Preserve the pinned version and public command syntax, and check APIs against that version. Reference: [official documentation](https://github.com/alecthomas/kong).

## Parsing and execution

- Express commands with `cmd` fields, positional arguments with `arg`, and defaults, environment names, enums, and required values with the corresponding tags. Tags describe parser semantics, not application invariants; validate relationships such as minimum <= maximum after resolution.
- Keep the CLI struct and parser fresh per invocation. `kong.New(&cli, options...)` followed by `parser.Parse(args)` exposes construction and parsing errors for a testable boundary. The package-level `kong.Parse` convenience function consumes process arguments and handles fatal errors, so avoid it inside reusable execution code.
- Handle help deliberately: Kong's help path can invoke its configured exit function even with an instance parser. Inject writers and use the pinned version's exit option for tests. A no-op exit callback may allow parsing to continue; prove that help cannot execute the command. Tests can intercept the exit with a sentinel recovered only at the test boundary.
- Dispatch with the returned context, commonly `ctx.Run(dependencies...)` to the selected command's `Run(...) error`. Bind typed dependencies rather than reaching into process globals. Check how interface-typed dependencies bind; a concrete-type binding may not satisfy an interface parameter. Return handler errors for one boundary to print and map to status. Completion support is not a reason to switch an existing stack to or from Kong.

## Configuration

Environment tags and resolvers are often sufficient. Built-in JSON configuration and optional external format loaders are separate decisions. Inspect resolver ordering and verify flag, environment, file, and default conflicts rather than transferring another library's precedence assumptions.

Kong's `Configuration` option provides defaults from configured search paths. If the user explicitly names a file, enforce the application's missing-file and parse-error contract; optional search behavior must not silently swallow an explicit request.
