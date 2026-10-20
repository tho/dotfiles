# Dependency signals without routine update churn

Default to two independent scheduled signals: vulnerability analysis of the committed dependency graph and compatibility tests against newer compatible versions. This follows [Filippo Valsorda's guidance](https://words.filippo.io/dependabot/). Commit upgrades according to project priorities rather than every upstream release, and treat applicable security findings as remediation work rather than an automatic merge.

## Committed graph

Run a pinned, compatible `govulncheck` on the dependencies actually selected by the repository, without first upgrading them. Schedule the check because vulnerability knowledge changes even when code does not. Cover relevant modules, build tags, platforms and supported toolchains, including the standard library used to build deployed software.

Reachability-aware results improve prioritization. A module-level match alone does not prove the application is affected, and a clean scan does not cover unknown vulnerabilities or every runtime path. Scanner failures must be visible. Applicable findings need assessment of exposure, deployment remediation and verification; raising a version alone may not address already exposed data or credentials.

## Compatibility experiment

Use a fresh disposable checkout and compare the committed graph with an experimental graph under the same toolchain and workload. In the experimental lane, `go get -u -t ./...` then the project tests exercises newer dependencies reachable from those packages. It does not migrate module paths to a new major version or guarantee coverage of all build-tagged packages and tools. Enumerate module roots and relevant package/tag sets deliberately.

Retain the selected versions, toolchain and failure output in logs. If only the upgraded lane fails, investigate a compatibility or toolchain-requirement change. If both fail, the experiment has not isolated an upgrade regression. Avoid automatic toolchain switching that silently changes both variables.

Do not commit changed module files, open version-bump PRs, publish artifacts or auto-merge from this job. Keep it separate from release gates on committed dependencies and visible to a responsible maintainer rather than swallowing failures. Schedule and manual dispatch are sufficient for this exploratory lane; ordinary PR checks continue testing the committed graph.

The dependency-compatibility asset contains both lanes inside a disposable sandbox. Adapt private-module access, replacements, vendoring, workspaces and supported tags explicitly. If vendored code is used, ensure the experiment actually tests the updated graph, for example with deliberate module mode inside the disposable lane; never accidentally test the old vendor directory after changing go.mod.

## Deliberate adoption and boundaries

Adopt fixes or features through reviewed changes with evidence from project tests and release constraints. Record any intentional deferral and owner; this default is not a freeze on upgrades. When asked to add or change a dependency bot, honor the explicit request with constrained permissions and no unsolicited auto-merge. Do not silently remove an existing bot configuration.

Go-module scanning does not cover GitHub Actions or container operating-system packages. Maintain action pins and image digests separately, and scan produced images where appropriate.

The article's examples are policy inspiration, not version pins to copy indefinitely.
