# rex-projects

A [Rex](https://www.superlogical.com/rex) Lua script for git projects. Pick a project, pick a branch, land in its session.

| Action | Key | Name | What it does |
|---|---|---|---|
| Switch Branch in Project… | `⌥⌘N` | `switch_project_branch` | `git switch` in the main checkout, then open its session |
| Open Worktree in Project… | `⌃⌥⌘N` | `open_project_worktree` | Open the branch in its own worktree and session |
| Clean Up Branch in Project… | | `clean_up_project_branch` | Delete a branch, its worktree and the session made for it |
| Add Project to List… | | `add_project` | Browse to a folder and add it |
| Remove Project from List… | | `remove_project` | Take a project off the list; its folder is untouched. One found under `roots` stays hidden until added again or its root is no longer set. Missing ones are marked and listed last |

Bind any of them with `rex.bind("ctrl+alt+cmd+c", "clean_up_project_branch")`.

## Install

Requires, on every host whose projects you want:

- Git 2.43+
- [worktrunk](https://worktrunk.dev) (`wt`) v0.83.0; its user config applies
- Rex server at control API revision 17+

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
  worktrees     = "~/.rex/worktrees",       -- worktrees go in <dir>/<repo>/<branch, / as ->; default: wt's worktree-path
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
- Run from a terminal inside one of the project's worktrees, that worktree's branch (`this worktree`) comes right after the default base, for stacking a branch on it. From the main checkout or elsewhere, the main checkout's branch comes there.
- Open Worktree accepts wt shortcuts: `^`, `-`, `pr:N`, or a PR link.
- A folder that isn't a repository just opens its session.

## Sessions

One session per checkout: `my-app` for the main checkout, `my-app · feat/x` for a worktree. The script uses, in order: the session it remembers for the checkout, the current session if its terminal is inside the checkout (adopted and renamed), or a new one. Sessions are tracked by id. The script closes only sessions it created.

## Pull requests

Open Worktree takes `pr:N` and runs `wt switch pr:N`, which uses [gh](https://cli.github.com) to find the PR on the project's own remote: same-repo branches track the remote, fork branches push to the fork. The session is labelled `my-app · #N`. Reopening goes to the existing worktree; update it with git yourself.

A PR link (`https://host/owner/repo/pull/N`, or any page of it) is taken only when its host and owner/repo match one of the project's remotes, and is then opened as `pr:N`. A remote behind an ssh host alias (`git@work:owner/repo`) matches on owner/repo alone. A bare number is a branch name.

## Hooks and clean up

wt hooks run for every branch Open Worktree opens and Clean Up removes, PRs and `^`/`-` included, as `wt switch` and `wt remove` run them in a terminal. An unapproved project hook fails the action and nothing changes; run `wt config approvals add` in the project.

Clean Up runs `wt remove --foreground --delete-branch <branch>` (never `--force`). wt refuses dirty worktrees. If the branch has unmerged changes you choose **Keep** or **Force delete**. The session is closed once git no longer lists the worktree.

To close the session when you run `wt remove` in a terminal, add to `~/.config/worktrunk/config.toml`:

```toml
[post-remove]
rex = "rex do close_project_session path={{ worktree_path }}"
```

To go to the checkout's session when you run `wt switch` in a terminal, creating a worktree or not, add:

```toml
[post-switch]
rex = '[ -n "$REX_PROJECTS" ] || rex do open_project_session path={{ worktree_path }}{% if pr_number %} pr={{ pr_number }}{% endif %}'
```

The session is found or made as in [Sessions](#sessions), with the same labels as Open Worktree, and the app switches to it (the app takes this from the CLI only with Remote Control on; on a remote host, see the known issue under [Install](#install)). A folder in no repository does nothing. rex-projects runs wt with `REX_PROJECTS=1`, so the hook skips Open Worktree's own `wt switch`, which opens the session itself.

With wt's default `cd = true` your terminal follows wt into the worktree, so whether its session is adopted depends on whether the shell got there before the hook asked. Add `[switch] cd = false` to keep the terminal where it is; the checkout's session has its own terminal there.

## Limits

- On a remote host each step must answer within 10 seconds; network calls (`git fetch`, and `wt switch` and `wt remove`, which run hooks and, for `pr:N`, gh) share 8 of them. Other remote `wt` calls run with `GIT_ALLOW_PROTOCOL=none`, so when the repo doesn't name its default branch (no `<remote>/HEAD`) wt guesses it from local branches and records it; run `wt config state default-branch clear` to reset it.
- A worktree deleted by hand stays stale until `git worktree prune` or Clean Up.

## Tests

```sh
lua5.1 test/run.lua   # or luajit; every flow, against a stand-in Rex, real git and wt (needs Perl)
rex do test/host.lua  # real session calls against a running Rex server
```
