# Viper

Viper resolves configuration independently of command parsing, including in services with no CLI. Keep instances explicit with `viper.New()` and resolve into a typed application config. Consult [the documentation](https://github.com/spf13/viper) and [API/source](https://pkg.go.dev/github.com/spf13/viper) matching the pinned version.

## Precedence and presence

Precedence is explicit `Set` > changed bound flags > environment > configuration file > remote key/value sources > defaults. An unchanged bound flag's default should not mask an environment/file value. `Set` is an override, not a defaults mechanism; use `SetDefault` for defaults. Bind flags before reading or decoding the resolved configuration and check binding errors.

Name environment variables deliberately with `BindEnv`, or a prefix and key replacer for automatic lookup. Include dot/hyphen replacements only as needed by the key scheme. Explicit names supplied to `BindEnv` can target external variables without the application prefix. Empty environment values are ignored by default; `AllowEmptyEnv(true)` changes that contract.

## Decoding

`AutomaticEnv` can make `Get` find a value without making that key discoverable to `Unmarshal`. Bind expected keys or register them with defaults; struct-binding alternatives are version-specific. A missing decoded boolean is not evidence that string-to-bool conversion is disabled: Viper's default decoder already enables weak typing in commonly used versions. Verify key discovery first.

Use `mapstructure` tags for nontrivial key mappings, return decoding errors, and validate the resulting struct. Check the pinned mapstructure import and decoder-hook signatures before adding hooks. `UnmarshalExact` can reject unknown fields when that is the application's contract. `Sub` may return nil; `UnmarshalKey` avoids dereferencing a missing subtree, but required sections still need validation.

## Files and sources

Separate optional search from explicit file selection. Ignore only the appropriate missing-file condition for optional discovery; propagate a missing explicitly selected file, permission failures, and malformed content. For versions returning `viper.ConfigFileNotFoundError` as a value, use `var missing viper.ConfigFileNotFoundError` with `errors.As(err, &missing)`, not a pointer target copied from an unrelated version.

`ReadConfig` loads reader content into the configuration layer, not the lower-priority defaults layer. Set its format explicitly. Embedded content plus disk overrides needs intentional merge order with `MergeConfig` or `MergeInConfig`; another replacement read can discard the base. Test nested keys and slices instead of assuming a particular deep-merge contract. Remote providers are optional dependencies; select one only for an explicit remote-configuration requirement and verify provider-specific failure behavior.

## Reload and isolation

Register change handling before starting the watcher. Validate a candidate configuration and publish an immutable snapshot only on success, retaining the previous snapshot on failure. Synchronizing the application snapshot does not make concurrent reads/writes of the Viper instance safe. Confine mutable resolver access to its owning reload path and serve application readers from the snapshot.

Test actual deployment update patterns, including atomic replacement and symlink changes, rather than asserting that only in-place writes work. Watcher implementations can watch directories to handle replacement. Verify watcher lifetime and shutdown support for the pinned version; garbage collection of a Viper variable is not a shutdown mechanism for a running goroutine. Use an explicitly owned watcher when bounded lifetime is required.

Use a fresh instance per test and avoid global `Reset` as an isolation strategy. Environment changes are process-wide, so do not parallelize tests that mutate them.
