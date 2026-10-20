# Reproduction and hypothesis testing

Beyond the evidence listed in SKILL.md, preserve the exact command, working directory, build flags, and relevant sanitized configuration. A reproduction that removes the failing behavior while simplifying has lost the signal.

## Focused experiments

Use an experiment to separate explanations, rather than accumulating diagnostic commands. For example: “A preceding test may leave process-global state behind. Under the same revision and environment, compare the suspect test alone with a sequence containing the suspected predecessor. Failure only after that predecessor supports state contamination; failure in isolation weakens that explanation. Then trace which state the predecessor changed.” This identifies an observation and its meaning without claiming the cause in advance.

Choose a focused package and test with `go test ./path/to/pkg -run '^TestSuspect$' -count=1 -v`, then change repetition, order, instrumentation, or timeout only for the selected hypothesis.

Choose a repeat count and timeout appropriate to the failing workload. Save the shuffle seed printed by Go and replay it with `-shuffle=<seed>` using the same selected tests. Repeated passes reduce uncertainty but do not prove an intermittent bug absent. Repeating in one test process may miss failures that require fresh process state.

`-parallel=1` limits tests using `t.Parallel` within a test binary; `-p=1` limits package-level execution. Neither serializes goroutines created by the application. Change these independently when testing a concurrency hypothesis and retain the conditions under which the failure occurs.

## Explain flakes before changing tests

Compare isolated and suite runs, fixture ownership, process globals, ports, temporary paths, environment, working directories, and completion signals. Trace the writer and reader of the disputed state. Order dependence and logical races can exist without a data race, and race instrumentation changes timing.

Use synchronization tied to completion when an assertion races asynchronous work. Use per-test resources when shared ownership is the cause.

## Regressions and environments

Compare a known-good and known-bad revision under equivalent inputs and environment. A bisection recommendation includes three decisions even when the repository is unavailable: an isolated checkout to protect current work, an oracle specific to the reported failure, and how the first bad change will be tested as a causal hypothesis. Request missing revisions or the failing command alongside that plan, rather than stopping at the request.

For many commits, use `git bisect run` in that isolated checkout with an oracle script shaped like this, replacing only the failure-specific check:

```sh
#!/bin/sh
go test -count=1 -run '^$' ./path/to/pkg || exit 125  # unbuildable revision: skip, never mark bad
go test -count=1 -run '^TestSuspect$' ./path/to/pkg   # oracle specific to the reported failure
s=$?; [ "$s" -gt 127 ] && exit 1                      # a status above 127 aborts git bisect run
exit "$s"
```

Finish with `git bisect reset` in that checkout. Skipped revisions may leave several candidates; retain that ambiguity.

Treat a first bad commit as a lead. Trace which changed condition violates the contract and confirm with a controlled experiment. CI-only failures may come from toolchain, build tags, OS, architecture, timezone, filesystem, resource limits, dependency availability, or test scheduling; inspect the differences relevant to the observed error instead of copying the entire environment into logs.
