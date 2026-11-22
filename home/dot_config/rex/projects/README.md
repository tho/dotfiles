# rex-projects

A [Rex](https://www.superlogical.com/rex) Lua script for git projects. Pick a project, pick a branch, land in its session.

| Action | Key | Name | What it does |
|---|---|---|---|
| Switch Branch in Project… | `⌥⌘N` | `switch_project_branch` | `git switch` in the main checkout, then open its session |
| Open Worktree in Project… | `⌃⌥⌘N` | `open_project_worktree` | Open the branch in its own worktree and session |
| Review Pull Request… | | `review_pull_request` | Open a pull request in its own worktree and session |
| Clean Up Branch in Project… | | `clean_up_project_branch` | Delete a branch, its worktree and the session made for it |
| Add Project to List… | | `add_project` | Browse to a folder and add it |
| Remove Project from List… | | `remove_project` | Take a project off the list; its folder is untouched. One found under `roots` stays hidden until added again or its root is no longer set. Missing ones are marked and listed last |

Bind any of them with `rex.bind("ctrl+alt+cmd+c", "clean_up_project_branch")`.

## Install

Requires, on every host whose projects you want:

- Git 2.43+
- [worktrunk](https://worktrunk.dev) (`wt`) v0.82.0; its user config applies
- Rex server at control API revision 17+
- [gh](https://cli.github.com), logged in, for Review Pull Request

Tools are found on the login shell's `PATH` (`$SHELL -l -c env`), so set `PATH` in a profile file.

Rex reads `~/.config/rex/init.lua` (`$XDG_CONFIG_HOME/rex/init.lua` when set, or the file `REX_CONFIG` names). Keep the script beside it as `projects.lua`, or keep this whole folder as `projects/` and require `projects.projects`.

1. Save `projects.lua` next to your `init.lua`.
2. Add `require("projects")` to `init.lua`.
3. Run `rex config reload`.

**Remote hosts:** install the same version on the Mac and on each remote host. Pickers run on the Mac; git, wt and the project list live on the focused session's host. Known issue: for a remote project the session is found or created, but the app doesn't switch to it ([Rex app bug](https://discord.com/channels/1546797889009881158/1564771883998650438)).

## Configure

All optional:

```lua
require("projects").setup{
  key           = "alt+cmd+n",              -- Switch Branch; false binds no key
  worktree_key  = "ctrl+alt+cmd+n",         -- Open Worktree; false binds no key
  base          = "main",                   -- default base for new branches; default: wt's default branch
  shell         = "/opt/homebrew/bin/fish", -- shell of new sessions; default: the account's shell
  worktrees     = "~/.rex/worktrees",       -- worktrees go in <dir>/<repo>/<branch, / as ->
  roots         = { "~/src" },              -- repositories in these folders are listed automatically
  project_order = "recent",                 -- "recent" or "name"
  branch_order  = "recent",                 -- "recent" (newest commit first) or "name"
  label         = nil,                      -- function(t) -> session label
  layout        = nil,                      -- function(t) -> initial_windows of a new session
  state_file    = nil,                      -- default: projects.json in the config folder
}
```

`label` and `layout` receive `{ project, branch, dir, host, pr, shell, label }`, where `label` is the script's own (`my-app`, `my-app · feat/x`, `my-app · #9`). They only affect new or adopted sessions; on error the script falls back to its own label and one shell tab. Example:

```lua
local function tab(name, t)
  return { window_label = name, layout = rex.layout.block{
    flavor = "com.superlogical.terminal.shell",
    options = { cwd = t.dir, shell = t.shell },
  } }
end

require("projects").setup{
  label  = function(t) return t.branch or t.label end,
  layout = function(t) return { tab("edit", t), tab("run", t) } end,
}
```

## Branches

The project picker lists the project containing the current terminal's folder first, then by last use (or name). Type a path to add a project.

An added project whose folder is gone is marked `missing` and listed last. Picking it offers **Keep** or **Remove from list**; nothing is removed unless you choose it, so a project on an unmounted disk just shows as missing.

| You pick | Switch Branch | Open Worktree |
|---|---|---|
| Local branch | `git switch` | New worktree and session |
| Existing worktree | not listed | Its session |
| `origin/x` | Creates local `x` tracking it | Same |
| New name | Asks for a base, creates it | Same, via `wt switch --create` |

- The first base offered is the default base's remote branch (e.g. `origin/main`), fetched before branching. Other bases are used as they are; local `main` is never moved.
- Open Worktree accepts wt shortcuts: `^`, `-`, `pr:N`, or a PR link.
- A folder that isn't a repository just opens its session.

## Sessions

One session per checkout: `my-app` for the main checkout, `my-app · feat/x` for a worktree. The script uses, in order: the session it remembers for the checkout, the current session if its terminal is inside the checkout (adopted and renamed), or a new one. Sessions are tracked by id. The script closes only sessions it created.

## Pull requests

Review Pull Request lists open PRs from `gh pr list` (review requests first), or takes a number or link. The checkout is `wt switch pr:<number>`: same-repo branches track the remote, fork branches push to the fork. Reopening goes to the existing worktree; update it with git yourself.

## Hooks and clean up

wt hooks run for your own branches. PR branches, `^` and `-` run with `--no-hooks`. An unapproved project hook fails the action; run `wt config approvals add` in the project.

Clean Up runs `wt remove --foreground --delete-branch <branch>` (never `--force`). wt refuses dirty worktrees. If the branch has unmerged changes you choose **Keep** or **Force delete**. The session is closed once git no longer lists the worktree.

To close the session when you run `wt remove` in a terminal, add to `~/.config/worktrunk/config.toml`:

```toml
[post-remove]
rex = "rex do close_project_session path={{ worktree_path }}"
```

## Limits

- On a remote host each step must answer within 10 seconds; network calls (`git fetch`, `gh`, hook-running `wt`) share 8 of them. Other remote `wt` calls run with `GIT_ALLOW_PROTOCOL=none`, so wt guesses the default branch locally; run `wt config state default-branch clear` to reset it.
- A worktree deleted by hand stays stale until `git worktree prune` or Clean Up.

## Tests

```sh
lua5.1 test/run.lua   # or luajit; every flow, against a stand-in Rex, real git and wt (needs Perl)
rex do test/host.lua  # real session calls against a running Rex server
```
