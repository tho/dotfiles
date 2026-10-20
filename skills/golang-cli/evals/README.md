# Evaluating Go CLI guidance

`cases.json` is the canonical suite; edit it first. `evals.json` copies its prompts, assertions and staged files for skill-creator tooling, without `fixture`, `checks` or `split`, so carry every case change across by hand. Its held-out cases carry the `heldout-` name prefix. The suite has fourteen development cases and two reserved transfer cases marked `split: heldout`; do not tune the skill against their outputs.

## Fixtures and execution

The five projects under `fixtures/` are deliberately defective starters, not examples to copy into applications. Each compiles, but its acceptance tests fail until the requested change is implemented. Module versions and checksums are pinned. Fixtures cover stdlib precedence/help/output, Cobra dry-run, Kong help return, ff v3 source precedence, and Viper environment decoding/validation.

Use a clean writable sandbox for implementation cases. Stage the files named by each case at their relative paths, then pass its input verbatim. Keep the tests and module manifests unchanged. Run the listed named Go tests independently after the agent finishes, with `-count=1` and a timeout. Reject test or dependency changes as an integrity failure; a passing transcript claim is not executable evidence. `checks` maps named tests to zero-based rubric expectation indices. Other expectations require transcript and code review.

Preload the pinned modules into an evaluation cache if network access is unavailable in the sandbox. Set `GOTOOLCHAIN=local` and use a compatible installed Go toolchain. Capture the exact harness command and environment in each report; do not silently change a project's default harness.

## Comparison and grading

Freeze cases, fixtures and rubrics before comparing the previous skill, revised skill and bare model. Stage only the skill entry and references, keeping evaluation answers and rubrics out of the skill's runtime context. Use identical fixtures and at least three repetitions per configuration. Preserve prompts, transcripts, workspaces, test output and per-expectation evidence.

Accept equivalent implementations with the same observable behavior. In particular, applying lower-priority defaults before parsing flags can be correct without `FlagSet.Visit`. Configuration constraints must come from the case, such as the port range in the Viper fixture. Explanation cases ask for a design or test proposal; implementation cases require actual working code. Keep those evidence standards distinct.

Report raw scores and rubric weaknesses together. The two transfer cases exercise related inputs and should be reported separately; they do not establish broad generalization by themselves.

## Trigger selection

Evaluate `group-triggers.json` with all converted skills under `skills-v2/` available together. `candidate_skills` must list every skill folder under `skills-v2/`; update it when a conversion is added. Legacy skills are excluded. Required selections missing from an attempt and selections outside its allowed set are failures. `triggers.json` holds the isolated trigger test, a different measurement that must be labeled separately.
