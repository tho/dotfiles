---
name: golang-cli
description: 'Builds and maintains Go CLIs and their configuration. Use when creating, extending, debugging, or reviewing Go commands, flags, arguments, help, completions, stdout/stderr output, signal handling, version flags, exit behavior, or CLI tests; choosing stdlib flag, Kong, ff, or Cobra; or working on flag, environment and file configuration precedence or Viper, including services without a CLI. Not for shell scripting or generic configuration-file editing.'
---

# Go CLI

Give maintainers commands that people and scripts can rely on: stable arguments, output, configuration, and exit behavior. Match the requested change or review to the existing CLI contract.

## Library choice

For new work prefer standard library, then Kong or ff, then Cobra or Viper. Start with `flag.FlagSet`; subcommands alone do not require a framework. Kong suits struct-based command models; ff suits flags-first configuration. Choose heavier libraries for a concrete requirement. Preserve an existing stack unless migration is requested. Command parsing and configuration are separate choices; Cobra does not require Viper.

Read only the applicable library reference, relative to this skill, when that library is requested, selected, or involved in the affected code. Library comparison needs the choice guidance above, not every reference. Check dependency versions and matching official APIs before implementing.

| Library | Reference |
| --- | --- |
| Kong | [Kong](references/kong.md) |
| ff, including ffcli | [ff](references/ff.md) |
| Cobra and pflag | [Cobra](references/cobra.md) |
| Viper, with or without a CLI | [Viper](references/viper.md) |

## Core contract

- Keep parsing and execution callable with supplied arguments, input, output writers, and context. Return errors or status to the process boundary; exit only after cleanup. Give each invocation fresh parser state.
- With stdlib, use `flag.NewFlagSet` and `flag.ContinueOnError`. Treat `flag.ErrHelp` as successful help. Parsing stops at the first positional argument or `--`; validate remaining arguments and dispatch subcommands explicitly. Boolean false requires syntax such as `-verbose=false`. Document that flags precede positionals; offer interspersed flags or short-flag bundles only through a library that provides them.
- Make one layer own diagnostic printing, including messages already emitted by the parser. Keep data on stdout, diagnostics on stderr, and help on the documented stream. Return write/flush errors. Keep machine output free of terminal decoration; a character device alone does not prove a TTY.
- Define precedence explicitly, normally explicit flags > environment > file > defaults. Track presence, not truthiness: `FlagSet.Visit` identifies supplied flags; `os.LookupEnv` distinguishes absent from empty. Explicit zero, false, empty, and default-equal values can override lower layers. Validate the resolved configuration. Distinguish optional discovery from an explicitly requested missing file and malformed files.
- Keep help, version, and completion usable without unrelated credentials or network setup. Separate usage from runtime failure; document status codes (commonly 0 success/help, 2 usage, 1 runtime) without claiming a universal convention. Use linker-injected version variables or build info with a development fallback.
- Propagate cancellation from `signal.NotifyContext` where signals matter. Stop notification and finish cleanup before returning; shutdown may need its own bounded context because the execution context is already canceled.

## Evidence

Verify affected behavior: help success, malformed flags/arguments, precedence including explicit zero values, separate streams, runtime failure status, and repeated invocations without state leakage. Use subprocess checks for actual exits or signals. Report checks run and gaps; review findings should name the broken CLI contract and triggering input.
