# Executable examples

Examples should show a caller using the real API successfully. Prefer an external `package foo_test` in a `_test.go` file to demonstrate the exported surface, following the repository's existing example file organization.

## Association and output

Name examples after declarations that exist (`Example`, `ExampleF`, `ExampleT`, `ExampleT_M`, plus a lowercase `_suffix` for variants); a `New` constructor takes `ExampleNew`, not an invented `ExampleNewClient`.

An `// Output:` directive makes `go test` execute the example and compare stdout, trimming leading/trailing whitespace. An empty directive asserts empty stdout. `// Unordered output:` ignores line order, not missing lines, duplicates, or different contents. Use it only when order is outside the contract. Without an output directive, an example is compiled but not executed.

Make asserted output reproducible: avoid real time, random values, unstable paths, live services, and nondeterministic ordering when they are incidental. Use local fixtures or in-process test servers for service examples and close resources. Do not conceal a behavior mismatch by changing expected output without checking the documented contract.

## Run and inspect

List matches first with `go test -list '^Example' ./path/to/package` and confirm the intended names appear, then run them with `go test -run '^Example' -count=1 -v ./path/to/package` and expect one `--- PASS` line per name; a pattern that matches nothing has verified nothing. Both commands compile package tests and can invoke `TestMain`; account for repository setup and side effects. Use exact example names when unrelated examples require external services. Retain relevant build tags and environment requirements.

Compile or run README/comment snippets in a temporary module that requires the project module through `replace <module> => <local checkout>`, with `GOTOOLCHAIN=local`, so the check exercises the current code rather than a published release or a downloaded toolchain. Label partial snippets as fragments; test them in a minimal wrapper when practical without implying the fragment runs by itself.
