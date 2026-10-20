# Cobra and pflag

Preserve an existing Cobra command tree or select Cobra for specific command ecosystem needs. Consult [Cobra's guide](https://github.com/spf13/cobra/blob/main/site/content/user_guide.md) and [pflag](https://pkg.go.dev/github.com/spf13/pflag) for the pinned versions.

## Construction and lifecycle

- Build a fresh command tree with explicit constructors and `AddCommand`, including independent flag storage per invocation. Global trees and registration in `init` complicate repeatable execution and tests.
- Use `Args` for positional validation, `RunE` for fallible execution, and `ExecuteContext` to supply cancellation. Cobra returns execution errors; the process boundary owns exit status. Direct `os.Exit`, `log.Fatal`, and `cobra.CheckErr` inside handlers bypass cleanup.
- Errors short-circuit the pre-run, run, post-run hook chain, so post-run hooks are not guaranteed cleanup; defer release where the resource is acquired.
- By default only the nearest applicable persistent hook runs. A child's hook can suppress root configuration/auth setup. Inspect `EnableTraverseRunHooks` and the pinned version before explicitly chaining hooks, or initialization may run twice. Keep help, version, and completion independent of unrelated initialization.
- If the boundary prints errors, set `SilenceErrors`; decide usage printing separately with `SilenceUsage`. Preserve concise usage guidance for invalid input without dumping help for operational failures. Silence settings do not classify errors or produce status 2 automatically.

## Flags and configuration seam

Local flags belong to a command; persistent flags are inherited by descendants. Watch shadowed names and parser differences from stdlib. Use pflag's `Changed` state to distinguish explicit values from defaults. Required and exclusive flag groups validate flag presence, not arbitrary configuration or business rules. Return errors from registration and binding calls that can fail.

Only bind Viper when it is actually used. Bind relevant flags before resolving configuration, using the executing command's effective flags to avoid sibling/local-name confusion. Read the resolved configuration, not merely the flag variable, when environment or files may win. A required Cobra flag is not automatically satisfied by a Viper environment value; validate the resolved value instead when any source is acceptable.

## Completion and generation

Use `ValidArgs` for static suggestions, `ValidArgsFunction` for positional completion, and `RegisterFlagCompletionFunc` for flag values. Completion suggestions are not runtime validation.

Directives such as `ShellCompDirectiveNoFileComp` and `ShellCompDirectiveFilterFileExt` are bitmask constants, not functions. For file-extension filtering, return extensions in the result slice with the filter directive. Bound dynamic lookup time and avoid destructive work or unrelated authentication during shell completion. Keep protocol output clean.

Use the existing completion command where available instead of adding a duplicate. Generate documentation from the constructed command tree with `cobra/doc` when requested; generation should not execute command handlers. Check actual help ordering and group validation rather than assuming registration order defines them.

## Verification

Capture `OutOrStdout` and `ErrOrStderr` separately through `SetOut` and `SetErr`; use `SetIn` for input and `SetArgs` for explicit arguments, with a new tree per test. Test real exit status at the process boundary rather than expecting `Execute` to terminate the process.
