# Documentation evaluations

`cases.json` is the runnable suite for BMad's `run_evals.py`; `evals.json` is the legacy source of cases 1 through 11. Do not regenerate `cases.json` with `convert_cases.py`: it expects `expectations`, not `assertions`, and silently produces empty rubrics. Cases 12 to 14 use fixtures for snippet execution, documentation auditing and executable-example repair.

## Fixture runs

Run native cases 12, 13 and 14 three times against both the skill and bare model. A run-specific harness must permit writes in its isolated workspace for documentation repairs and Go caches. Keep repository/global harness configuration unchanged, disable Go dependency/toolchain downloads, and stage each case's declared `files` using paths relative to this directory. These standard-library-only fixtures need no network access for Go commands.

The available toolchain may be newer than each fixture's Go 1.22 floor. Report the actual version and leave minimum-version execution unverified unless it is separately tested. Fixtures intentionally contain stale comments, README instructions and a broken example. Do not fix those checked-in inputs: the evaluated agent repairs only its staged copies. After the run, `git status --porcelain -- skills-v2/golang-documentation/evals/fixtures` must print nothing, and each staged production `.go` file and `go.mod` must pass `cmp` against its fixture.

```bash
python3 -B .agents/skills/bmad-eval/scripts/run_evals.py \
  --cases skills-v2/golang-documentation/evals/cases.json \
  --skill-path skills-v2/golang-documentation \
  --case-ids 12,13,14 --mode baseline --runs 3 \
  --harness <isolated-workspace-write-harness.json> \
  --output-dir _bmad-output/eval-reports
```

Preserve prompts, transcripts, workspaces, timings and evidence-based grades in a new dated run directory. Do not overwrite the original run when repairing a case. Grade actual snippet/example execution from tool results, not from a proposed command or a package build with no tests.

## Trigger runs

`triggers.json` holds single-skill should/should-not cases for `run_triggers.py`. `group-triggers.json` defines required and allowed selections with all converted `skills-v2/` skills available together. Exclude `skills/`. Count missing required selections and loads outside the allowed set separately. Refresh the candidate list when converted skills are added. These documentation-focused cases are not a full regression suite for every sibling.
