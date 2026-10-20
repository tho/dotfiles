# Workflow trust boundaries

For each job, identify which actor controls its code, which revision is checked out, what credentials and caches it can access, and which later jobs trust its output. A YAML `permissions` block constrains the GitHub token, not all authority present on a runner.

## Events and permissions

Use `pull_request` for testing untrusted PR code. Do not check out or execute that code with `pull_request_target` or a privileged `workflow_run` consumer. Metadata jobs that need elevated permissions must not evaluate PR-controlled scripts, expressions or artifacts. Pass untrusted text through quoted environment variables instead of interpolating it into shell source.

Default to `contents: read`, disable checkout credential persistence, and grant extra permissions only to the job that needs them. Secrets and environment-scoped credentials belong in trusted publishing jobs. A bot actor check or a tag prefix does not establish provenance; constrain who can create release tags and approve protected release environments. Do not change repository settings merely because a template recommends them.

Use disposable hosted runners for untrusted execution or provide equivalent isolation. A self-hosted runner with persistent workspaces, internal network access or mounted credentials needs a separate threat assessment. Read-only permissions do not remove cache-write capabilities or isolate neighboring steps.

## Dependencies, caches and artifacts

The scheduled newer-dependency template runs in `geomys/sandboxed-step` with credential persistence disabled and workspace writes discarded. Keep package downloads and test execution inside the same sandbox so changes do not need to escape it. Disable setup-go caching and do not restore or save shared build/module caches for that experiment. Its output is a compatibility signal, never a source of release binaries or dependency commits.

The sandbox still has network access for public modules and does not make hostile code harmless to the network. Use an appropriate isolated runner/network for private modules or internal services; do not forward broad credentials to make an example work. Pin and review the sandbox action and root filesystem image like other execution dependencies. Its default rootfs tag is mutable; resolve an approved digest for a reproducible deployment.

Treat artifacts from untrusted jobs as untrusted data. Do not execute them in a write-token job or allow them to supply configuration, scripts or dependency trees for release. Cache keys alone do not create a trust boundary; separate producers and consumers by trust level or disable cache reuse.

## Version selection

Pin external actions to verified full commit SHAs with a readable release comment; for an annotated tag, take the peeled `^{}` commit from `git ls-remote --tags`, because the tag object SHA is not a commit. A mutable major tag is a version selector, not an immutable pin. Review release notes and runner requirements when updating; a newer Node-based action can require a newer runner. Keep linter, scanner and release-tool versions explicit and compatible with their configurations. Refresh deliberately instead of installing an update bot as an incidental CI change.

The bundled pins match the release named in each comment. They are reviewable examples, not a claim to remain current. The examples target hosted Ubuntu 24.04; verify self-hosted and GitHub Enterprise compatibility before reuse.

Sources: [GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use), [sandboxed-step](https://github.com/geomys/sandboxed-step).
