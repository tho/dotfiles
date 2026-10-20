# Checks that carry useful evidence

Read the existing workflow, module files, support policy and test commands. Preserve their intent, including private modules, CGO, build tags and integration services. A workflow task does not justify replacing the local linter policy or adding an unrelated scanner suite.

## Tests and builds

Cover the declared support floor and current stable Go where appropriate. Keep versions quoted in YAML, since an unquoted `1.20` parses as the number 1.2. An explicit floor with `GOTOOLCHAIN=local` catches accidental use of newer language or standard-library features; automatic toolchain downloads can otherwise hide the mismatch. `setup-go` may honor a `toolchain` directive when reading a module file, so inspect the effective version rather than calling that job a minimum-version test by assumption.

Use `fail-fast: false` to retain independent matrix evidence. Run a race-enabled job on a supported platform with its required compiler/CGO support; do not blindly add `-race` to every cross target. Preserve shuffle seeds in logs. Use `-count=1` when integration tests must contact fresh services. Keep service startup health checks, test deadlines and cleanup bounded. Add an integration build tag only if the project actually uses one.

`go build ./...` is a compile check, not a test of every platform or module. Add only supported OS/architecture combinations and ensure CGO cross-compilation has the required C toolchain. Run each module explicitly in a multi-module repository; a root `./...` does not recursively test nested modules. Use `GOWORK=off` for independently released module checks so workspace replacements cannot conceal missing released dependencies.

## Lint, metadata and coverage

Wire the project's lint command and configuration into CI. Verify the linter version supports the chosen Go toolchain and configuration schema. Avoid running identical analyzers twice without a reason. Keep a standalone `go vet` job only where it supplies additional coverage or is the selected minimal check.

Check tidy consistency with the project's canonical toolchain in a disposable checkout. Use `go mod tidy` followed by a failing check for modified and newly created module metadata, such as `test -z "$(git status --porcelain -- go.mod go.sum)"`. A tracked-file-only diff misses a newly created go.sum. `go mod verify` checks module-cache integrity; neither it nor a download proves dependency safety.

Coverage reporting and thresholds follow project requirements; no arbitrary percentage or paid service is mandatory. Preserve test failure status when collecting coverage, and avoid racing matrix uploads into one unnamed report. Report generation alone does not enforce a gate; required status settings must name the relevant check.

## Security checks

Run `govulncheck` against the committed graph on PRs, trusted branch changes and a schedule. Match relevant build tags, platforms and modules; static reachability reduces noise but is not proof that all runtime behavior is safe. Distinguish applicable findings, informational matches, and scanner execution errors. Do not hide scanner failure with `continue-on-error`, `|| true`, or a no-fail flag on a purported blocking job.

Add CodeQL, gosec or container scanning for a defined coverage gap and compatible repository plan. SARIF upload is reporting; establish separately what blocks merging. Limit upload permissions to that job and handle fork restrictions without granting untrusted jobs secrets. Scanner setup belongs here; assessing an application vulnerability can use the optional `golang-security` skill.

## Templates and acceptance

The CI asset is a single-module Go 1.26+ example with an existing golangci-lint v2 configuration. Adapt the support floor, module paths and tools before installing it. Save it as a reusable workflow at the destination referenced by the release assets. Validate YAML/expressions with `actionlint`, run the actual commands locally when possible, and distinguish these checks from a hosted workflow run.

Use a known failing test or scanner fixture to demonstrate that the job fails; a happy-path run alone cannot show whether an exit code was swallowed. Confirm that branch protection or rulesets require stable check names and that event/path filters do not leave required jobs permanently pending. Include `merge_group` if the repository uses GitHub's merge queue.

Sources: [setup-go](https://github.com/actions/setup-go), [Go vulnerability tutorial](https://go.dev/doc/tutorial/govulncheck), [actionlint](https://github.com/rhysd/actionlint).
