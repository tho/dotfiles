---
name: golang-project-setup
description: 'Sets up Go module and repository layouts. Use when starting a Go project or running go mod init, choosing where main.go, cmd/, internal/ or pkg/ go, organizing binaries and library packages, choosing a module path or vanity import identity, deciding one module vs several in a monorepo, setting up go.work workspaces, or reorganizing a repository into new modules. Not for moving packages in an already chosen structure (golang-maintenance), package architecture or API contracts (golang-design), CLI flags (golang-cli), dependency upgrades (golang-dependencies), or CI workflows (golang-ci-release).'
---

# Go Project Setup

Act as a Go project setup partner. Produce a layout proposal or working repository that its maintainers can build, test, and extend without this conversation. Tie each package, binary, and module boundary to a concrete consumer, deployment, or release need.

Use the repository and supplied requirements to establish executables, importable APIs, release boundaries, and supported Go versions. Ask only for missing facts that change the structure, such as the intended public import path; a named architecture or DI framework is not one of them.

## Layout decisions

- Start with one module. Multiple packages or binaries alone do not justify multiple modules. A workspace coordinates local development across modules with independent reasons to exist.
- A small executable can keep its main package at the root. Separate binaries can use one directory each under `cmd/`. Public libraries can live at the module root or in ordinary subdirectories; `pkg/` has no special visibility semantics.
- Use `internal/` for packages restricted to the enclosing import subtree. Choose cohesive package responsibilities rather than filling a standard directory tree.
- Preserve existing module paths and supported versions unless changing them is part of the request. A public module path is an import identity, which can use a vanity domain; do not mechanically lowercase or rename it to fit a style rule.

Load [layout and initialization](references/layout-and-initialization.md) for concrete layouts, module paths, and supporting files. Load [workspaces](references/workspaces.md) for module splits or local multi-module development. Load [reorganization](references/reorganization.md) before changing an existing layout.

## Deliver and verify

Match the request: advice gives a justified tree and commands; setup applies the authorized changes. Scaffold only the files the stated behavior needs, since every extra layer is code the maintainers must carry: retain established choices, prefer a flat package and manual wiring, and add Cobra, Viper, DI, a linter, or a Makefile only when a requirement calls for it. Leave agent instruction files such as AGENTS.md as they are unless the request covers them.

For implemented changes, format changed Go files and run the relevant build and test commands from each affected module. Check explicit command packages when binaries are promised. Workspace success alone does not verify that independently released modules work outside it; use the checks in the workspace reference.

Report the layout rationale, compatibility effects, executed checks, and unresolved decisions or failures. Distinguish proposed commands from evidence of a working project.
