# Release the revision that passed

Identify the artifact contract first: importable module, executable archive, container image, or several independently versioned modules. Keep the release path small enough that the evidence can be traced from tag to source commit to artifact.

## Validation and authority

Use a tag-triggered workflow with fresh gates on that event's exact commit, or verify successful checks for that exact SHA. A previous green default-branch build and a `v*` tag alone are insufficient. Restrict tag creation through repository rules, validate release-tag semantics, and choose an approval environment where the project requires it. Grant publishing permissions only after read-only checks succeed.

A failed, skipped or canceled validation must not reach publication. Avoid `always()` on the publishing job. Serialize releases by tag without canceling an in-progress publication. Retrieve enough history for version and changelog generation, commonly `fetch-depth: 0`.

A release environment named in YAML is not an approval policy by itself. Report the rules or reviewers the maintainer must configure. Creating a workflow does not authorize creating tags, uploading packages, publishing releases or altering host settings during the current task.

## Libraries and binaries

Libraries normally need versioned tags and optional release notes, not cross-compiled archives. Follow module-path major-version rules and subdirectory tag prefixes for independently released modules. Workspace replacements must not be required by consumers. A simple GitHub Release can suffice; if GoReleaser is chosen, use a library-appropriate configuration rather than inventing a main package.

For programs, use GoReleaser with actual main-package paths, binary names, supported targets and real version variables. Do not disable CGO unless the program supports it. Distinct build IDs and artifact names prevent multi-binary collisions. Cross-compilation does not prove the output runs on the target OS.

The binary asset assumes one pure-Go command at `./cmd/app`; replace it with the real path. Copy the configuration to the release tool's expected destination and validate with `goreleaser check`. A local `goreleaser release --snapshot --clean` exercises build/archive generation without publishing. Avoid publishing hooks or external integrations in a dry run unless their behavior is understood.

## Containers

Build PR images without login or push credentials. On trusted tags, build from the checked-out validated revision, publish only to requested registries, and retain the immutable digest. Adapt platform targets to the Dockerfile and CGO needs. Never pass credentials as Docker build arguments or bake them into layers.

BuildKit SBOM and provenance attestations are not the same as GitHub artifact attestations or a signature. `provenance: mode=max` and `sbom: true` do not by themselves require `id-token: write` or `attestations: write`; add those permissions only for a separate attestation/signing integration that actually uses them. Inspect provenance for sensitive build parameters.

If vulnerability scanning is a publishing gate, scan the actual candidate artifact, not a separately rebuilt approximation. For multiple platforms, account for each published platform. Keep candidate validation and final publication connected by digest; report any tool or registry limitation instead of claiming an unscanned platform passed.

## Templates and sources

The release and container examples call reusable workflows installed as `.github/workflows/ci.yml` and `.github/workflows/govulncheck.yml`, plus the binary configuration at `.goreleaser.yml` when applicable; keep these gates or replace them with equivalent exact-revision gates. The examples accept v-prefixed SemVer tags, including prereleases; adapt the validator for independently versioned submodules. The vulnerability and binary-release examples select the same project toolchain from go.mod. A container Dockerfile may select another compiler: align its scan with that compiler and scan its runtime image separately, since the Go gate covers neither that mismatch nor OS packages. The assets are ordinary inputs to adapt, not a hidden runtime dependency of the skill.

Sources: [GoReleaser configuration](https://goreleaser.com/customization/), [Go module release workflow](https://go.dev/doc/modules/release-workflow), [Docker build-push inputs](https://github.com/docker/build-push-action).
