# ff

Use ff when flags define the configuration surface and environment/file input should populate it. Keep the project's module major version. [v3 documentation](https://pkg.go.dev/github.com/peterbourgon/ff/v3) and [the upstream README](https://github.com/peterbourgon/ff) describe different API generations; inspect the module declaration rather than copying main-branch examples into older code.

## v3

- Define a stdlib `flag.FlagSet` with `flag.ContinueOnError`, then call `ff.Parse(fs, args, options...)` instead of parsing once with each library. Return its error and recognize `flag.ErrHelp`; parser output and boundary output must not duplicate diagnostics.
- Enable environment/file sources explicitly. `ff.WithEnvVarPrefix` namespaces environment names. `ff.WithConfigFileFlag` identifies the flag containing a filename, and `ff.WithConfigFileParser` chooses its format. `ff.PlainParser` is not a YAML parser.
- Check custom repeatable flags separately: accumulating `flag.Value` implementations can behave differently from scalar replacement. Test conflicts rather than assuming every custom setter is idempotent.
- For command trees, v3's separate `ffcli` package offers `ffcli.Command` with a `FlagSet`, `Subcommands`, and an `Exec(context.Context, []string) error` handler. Validate positional arguments in the handler and return failures; avoid implicit Cobra-style persistent hooks or flag inheritance assumptions.

## v4 and migration

Verify v4 release status before adopting it. v4 offers `ff.FlagSet` and `ff.Command` in the main package, alongside parsing support for stdlib flag sets. Use v4 types and method signatures only in a module that declares ff/v4; v3's `ffcli.Command` examples do not transfer. A version upgrade is a separate compatibility decision, not part of adding one flag.

## Boundary checks

Check environment-name mapping, empty environment values, and flag placement around subcommands. ff already covers environment and file sources, so they are no reason to add Viper. Keep help consistent with the actual configuration surface.
