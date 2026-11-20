# rex-projects

A [Rex](https://www.superlogical.com/rex) Lua script for git projects. Pick a project, pick a branch, land in its session.

| Action | Key | What it does |
|---|---|---|
| Switch Branch in Project… | `⌥⌘N` | `git switch` in the project's main checkout, then open its session |
| Open Worktree in Project… | `⌃⌥⌘N` | Open the branch in its own worktree, with its own session |
| Clean Up Branch in Project… | none | Delete a branch, its worktree and that worktree's session |
| Add Project to List… | none | Browse to a folder and add it |
| Remove Project from List… | none | Forget a project; its folder is untouched |

All five are in the palette's **Projects** section. **Projects: Backend** in the **Internal** section is used by the script itself and does nothing when you run it.

## Install

Requires Git 2.23+ on the server's `PATH` and a Rex server at control API revision 17 or newer. On older servers the script does nothing.

1. Save `projects.lua` next to your `init.lua` (see [file location](https://www.superlogical.com/rex/docs/customize/config#file-location)).
2. Add to `init.lua`:

   ```lua
   require("projects")
   ```

3. Run `rex config reload`.

### Remote hosts

Install the same version of the script on the Mac that runs the Rex app and on every remote host whose projects you want. When you update it, update and reload it everywhere.

The pickers always run on the Mac. The projects come from the host of the focused session: that host's copy lists the folders, runs git, and stores the project list. A host without the script fails with a message saying so.

Known issue: for a project on a remote host the session is found or created, but the app does not switch to it. Go to it by hand. This waits on a [Rex app bug](https://discord.com/channels/1546797889009881158/1564771883998650438).

## Configure

All settings are optional.

```lua
require("projects").setup{
  key           = "alt+cmd+n",        -- Switch Branch in Project…; false binds no key
  worktree_key  = "ctrl+alt+cmd+n",   -- Open Worktree in Project…; false binds no key
  base          = "main",             -- default base of a new branch
  shell         = "fish",             -- shell of a new session; default is the account's shell
  worktrees     = "~/.rex/worktrees", -- new worktrees go in <dir>/<project>/<branch>
  roots         = { "~/src" },        -- repositories in these folders are listed without adding them
  project_order = "recent",           -- project picker order: "recent" (last used first) or "name"
  branch_order  = "recent",           -- branch list order: "recent" (newest commit first) or "name"
}
```

- `REX_WORKTREES` and `REX_PROJECTS` set the worktree folder and one scan root when `setup` doesn't.
- `shell` is a name or a path, such as `fish` or `/bin/zsh`. Set it to match the app's Startup Command (Settings > Terminal > Shell): that setting only applies to terminals the app opens itself, such as new tabs, and a script cannot read it. Like `base`, it is read on the host that has the project.
- `base` is read on the host that has the project. If nothing there has that name, the base list starts with the main checkout's branch.
- State (the project list, the order of last use and each checkout's session id) is kept in `projects.json` in your [config folder](https://www.superlogical.com/rex/docs/customize/config#file-location).

### Other keys

`setup` binds only the two keys above. To bind any other action, call `rex.bind` with its action name in `init.lua`:

```lua
rex.bind("ctrl+alt+cmd+c", "clean_up_project_branch")
```

| Action | Name |
|---|---|
| Switch Branch in Project… | `switch_project_branch` |
| Open Worktree in Project… | `open_project_worktree` |
| Clean Up Branch in Project… | `clean_up_project_branch` |
| Add Project to List… | `add_project` |
| Remove Project from List… | `remove_project` |

## Picking a branch

Switch Branch and Open Worktree both show the project picker, then one list of branches. Choose a row or type a name. The project picker lists the project you last switched, opened or went to in either action first, then the others in order of last use, then projects never opened, by name. With `project_order = "name"` it lists them all by name.

| You pick | Switch Branch | Open Worktree |
|---|---|---|
| A local branch | `git switch`, then the project's session | A new worktree and a session for it |
| An existing worktree | Not listed | Its session |
| A remote branch `origin/x` | Creates local `x` tracking it, then as a local branch | Same |
| A name that matches nothing | Creates the branch, then as a local branch | Same |

- **New branches** always ask for a base. The list has the default base first, then the main checkout's branch, then every other branch. You can also type one, such as `origin/main`. A branch started from a remote branch does not track it (`--no-track`).
- **Remote branches** are listed as `<remote>/<branch>` unless a local branch has the same name. Nothing is fetched, so the list shows what you fetched last.
- **Hidden rows:** Switch Branch does not list branches held by a worktree, and Open Worktree does not list the main checkout's branch. Typing such a name shows git's refusal.
- Spaces in a typed name become dashes.
- A folder that is not a repository has no branch list. Both actions go straight to its session.

## Adding a project

**Add Project to List…** and the **Add project…** row of the project picker open a folder browser. Return on a repository adds it, Return on any other folder opens it, and the first row adds the folder you are in.

You can also type a path, in the browser or in the project picker itself, and press Return on the last row:

- A repository is added.
- Any other folder opens in the browser.
- A path that does not exist opens the nearest folder above it, filtered by the part that was not found. `/usr/lo` opens `/usr` filtered by `lo`.
- A path that does not start with `/` or `~` is inside the folder being browsed.

The list is not filtered by path while you type. The palette filters only the rows already on screen, so a path takes effect on Return.

## Sessions

Each checkout has one session: `my-app` for the main checkout, `my-app · feat/x` for a worktree. The script picks it in this order:

1. The session it remembers for that checkout, if it still exists.
2. The session you ran the action from, if its terminal is inside the checkout. It is renamed and remembered, unless it is already remembered for another checkout.
3. A new session.

Sessions are tracked by id, so renaming one is safe. Switch Branch never opens a second session for a project.

## Cleaning up a branch

Pick a project, then a branch. The main checkout's branch is not listed, because git cannot delete it.

1. If the branch's worktree has changed or untracked files, the action fails and says so: `Nothing was deleted: the worktree of <branch> has uncommitted changes. Commit or discard them, then clean up again.`. Ignored files do not count. This check cannot be overridden.
2. The worktree is removed (`git worktree remove`) and the branch is deleted (`git branch -d`).
3. If git refuses to delete the branch, which is usual after a squash or rebase merge, you choose **Keep** or **Force delete** (`git branch -D`). Either way the worktree stays removed.
4. The worktree's session is closed, stopping whatever runs in it.

## Errors and limits

- When git refuses a step, the action fails with git's message, which the app shows as the action's error. Nothing further changes.
- Each step on a remote host must answer within 10 seconds. A slower step fails the action, though git may still finish it. If a clean-up times out, the worktree may be gone while its session is still open; close it by hand.
- Commands run through `rex.exec` with argument lists, never a shell, so paths with spaces or quotes are safe.

## Tests

```sh
lua5.1 test/run.lua     # every flow, with a stand-in for Rex and real git
rex do test/host.lua    # the real session calls, against a running Rex server
```

`test/host.lua` creates a few sessions on the server it runs against and closes them again. It answers the pickers itself and never asks the app to show a session.

Verified on Linux with Git 2.47 and a Rex server at control API revision 18:

- `test/run.lua`: both branch actions, the base step, the three ways a session is found, clean-up with its refusal and force offer, plain folders, and all of these through a stand-in for the app's relay to another host.
- `test/host.lua`: creating, finding and adopting sessions, and clean-up removing worktrees and closing their sessions.
- The palette section, both keys, and `setup` rebinding or removing them, checked in a real server's keymap.

Not verified:

- The pickers in the Mac app's palette. Only test code answered them.
- A remote host end to end from the Mac app. Only the stand-in covers it.
- The Windows and macOS code paths (`cmd`, `dir`, `%APPDATA%`, the login shell). They have not been run in this version.
