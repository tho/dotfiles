# rex-projects

A [Rex](https://www.superlogical.com/rex) Lua script for git projects. Pick a project, pick a branch, land in its session.

| Action | Key | What it does |
|---|---|---|
| Switch Branch in Project… | `⌥⌘N` | `git switch` in the project's main checkout, then open its session |
| Open Worktree in Project… | `⌃⌥⌘N` | Open the branch in its own worktree, with its own session |
| Review Pull Request… | none | Open a pull request in its own worktree, with its own session |
| Clean Up Branch in Project… | none | Delete a branch, its worktree and the session the script made for it |
| Add Project to List… | none | Browse to a folder and add it |
| Remove Project from List… | none | Forget a project; its folder is untouched |

All six are in the palette's **Projects** section. **Projects: Backend** in the **Internal** section is used by the script itself and does nothing when you run it. **Projects: Close Checkout Session** (`close_project_session`), also Internal, is for wt's post-remove hook (see [Closing a session from a terminal](#closing-a-session-from-a-terminal)); run from the palette it has no path and does nothing.

## Install

Every host whose projects you want needs:

- Git 2.43+.
- [worktrunk](https://worktrunk.dev) (`wt`), tested with v0.82.0. It makes and removes the worktrees, finds the default branch and checks out pull requests. Its user config (`~/.config/worktrunk/config.toml`) applies, except for what the script sets on each call: the worktree location, `--delete-branch`, and `--no-hooks` for pull requests, `^` and `-`.
- A Rex server at control API revision 17 or newer. On older servers the script does nothing.

git, wt and gh are found on the login shell's `PATH`. The script runs `$SHELL -l -c env` once and takes from it `PATH`, `SSH_AUTH_SOCK`, `XDG_CONFIG_HOME`, `GH_HOST`, `GH_CONFIG_DIR`, `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` and `GITHUB_ENTERPRISE_TOKEN`. A login shell reads its profile files, such as `~/.zprofile` (zsh), `~/.bash_profile` (bash) or `config.fish` (fish), but not `~/.zshrc` or `~/.bashrc`. So set `PATH` in a profile file. If `$SHELL` is unset, or the shell fails or takes over 5 seconds, the script logs a warning and the tools use the server's own environment.

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
  base          = "main",             -- default base of a new branch; unset, the default branch wt finds
  shell         = "fish",             -- shell of a new session; default is the account's shell
  worktrees     = "~/.rex/worktrees", -- new worktrees go in <dir>/<repository>/<branch>
  roots         = { "~/src" },        -- repositories in these folders are listed without adding them
  project_order = "recent",           -- project picker order: "recent" (last used first) or "name"
  branch_order  = "recent",           -- branch list order: "recent" (newest commit first) or "name"
  label         = nil,                -- a function giving a session's label; see below
  layout        = nil,                -- a function giving a new session's tabs; see below
  state_file    = nil,                -- where the state is kept; default projects.json in the config folder
}
```

For example, sessions named after the branch alone, and new ones with two tabs:

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

- `setup` warns about an unknown option or a value it doesn't allow, naming the option, and keeps that option's previous value. The rest of the call applies.
- `false` unsets `key`, `worktree_key`, `base`, `shell`, `label` and `layout`.
- `worktrees` goes to every `wt` call as `worktree-path = "<dir>/{{ repo }}/{{ branch | sanitize }}"`, over wt's own `worktree-path`. `{{ repo }}` is the name of the main checkout's folder, and a `/` in the branch becomes `-`.
- `shell` is a name or a path, such as `fish` or `/bin/zsh`. Set it to match the app's Startup Command (Settings > Terminal > Shell), which reaches only terminals the app opens itself and which a script cannot read.
- `base` and `shell` are read on the host that has the project. If no branch there is called `base`, the base list starts with the main checkout's branch.
- Without `base`, the default branch is what `wt config state default-branch` says. wt records it in the repository's git config (`worktrunk.default-branch`) the first time, from `refs/remotes/origin/HEAD`, else by asking the remote for up to 10 seconds, else by guessing from the local branches. After the default branch is renamed on the server, run `wt config state default-branch clear`.
- `label` and `layout` are functions given `{ project, branch, dir, host, pr, shell, label }`: the project's name, the branch checked out (nil for a plain folder or a detached HEAD), the checkout's folder, the session's host (nil for this machine), the pull request's number, the `shell` setting, and rex-projects' own label (`my-app`, `my-app · feat/x`, `my-app · #9`).
  - `label` returns a string. It names a new session, or one adopted from your terminal.
  - `layout` returns the `initial_windows` list of `session.create`. It shapes only a new session.
  - A session that is already the checkout's is left as it is.
  - If either one fails or returns something else, or the server refuses the windows, the action logs a warning and uses rex-projects' own label or one shell tab.
  - Both run in the `init.lua` of the machine the app runs on, for sessions on every host.
- The state is kept in `projects.json` in your [config folder](https://www.superlogical.com/rex/docs/customize/config#file-location), or in the file `state_file` names: the project list, the order of last use, and each checkout's session, with whether the script made it. Where the server's Lua has no `io` library, the state lasts until the server restarts, and the log says so.

### Other keys

`setup` binds only the two keys above. To bind any other action, call `rex.bind` with its action name in `init.lua`:

```lua
rex.bind("ctrl+alt+cmd+c", "clean_up_project_branch")
```

| Action | Name |
|---|---|
| Switch Branch in Project… | `switch_project_branch` |
| Open Worktree in Project… | `open_project_worktree` |
| Review Pull Request… | `review_pull_request` |
| Clean Up Branch in Project… | `clean_up_project_branch` |
| Add Project to List… | `add_project` |
| Remove Project from List… | `remove_project` |

## Picking a branch

Switch Branch and Open Worktree both show the project picker, then one list of branches. Choose a row or type a name.

The project picker, in every action, lists:

1. The project that holds the folder of the terminal you ran the action from, a worktree counting as part of its project. Of two listed folders that both hold the terminal's folder, the deeper one is first.
2. The others in order of last use, the last one you switched, opened or went to first.
3. Projects never opened, by name.

With `project_order = "name"`, all but the first are listed by name.

| You pick | Switch Branch (`git switch`) | Open Worktree (`wt switch`) |
|---|---|---|
| A local branch | `git switch`, then the project's session | A new worktree and a session for it |
| An existing worktree | Not listed | Its session |
| A remote branch `origin/x` | Creates local `x` tracking it, then as a local branch | Same |
| A name that matches nothing | Creates the branch, then as a local branch | Same, with `wt switch --create x --base <base>` |

- **New branches** always ask for a base: the default base first, then the main checkout's branch, then every other branch. You can also type one, such as `origin/main`, or any commit.
- **Tracking:** in Switch Branch, a new branch from a remote base does not track it (`--no-track`). In Open Worktree, it tracks a remote base of the same name only: `x` from `origin/x` tracks it, `x` from `origin/main` does not.
- **The default base is fetched.** When the default base has a remote branch, the first row is that branch, such as `origin/main`, marked `default · fetched first`. That is the branch the local one tracks, else `origin/<base>`, or `base` itself when it names a remote branch. Choosing it fetches that one branch and starts from it. If the fetch fails, the action stops with git's message.
- **Every other base is used as it is,** local `main` with its unpushed commits included. Local `main` is never moved.
- **Remote branches** are listed as `<remote>/<branch>` unless a local branch has the same name. Apart from the default base, nothing is fetched, so the list shows what you fetched last.
- **Hidden rows:** Switch Branch does not list branches held by a worktree; typing one shows git's refusal. Open Worktree does not list the main checkout's branch; typing it goes to the project's own session.
- **wt's shortcuts** work in Open Worktree: `^` is the default branch, `-` the branch wt switched to before (`wt switch -`), and `pr:N` or a pull request link (`https://…/pull/N`) opens that pull request as Review Pull Request does. Switch Branch refuses them and says what takes them.
- A bare number such as `123` or `#12` is a branch name. A name that git reads as another branch, such as `@` or `@{-1}`, is refused.
- Spaces in a typed name become dashes.
- A folder that is not a repository has no branch list. Both actions go straight to its session.

## Hooks

wt runs hooks only for your own branches.

- Open Worktree, making a worktree for a local branch, a remote branch or a new name, and Clean Up, removing your own branch, run your hooks and the project's `.config/wt.toml` hooks, as in a terminal.
- A pull request's branch (marked `branch.<name>.rex-pr`), `^` and `-` run none (`--no-hooks`), because a pull request's hooks come from whoever wrote it.
- A project hook you have not approved fails the action, naming the hook's command, and nothing is made or removed. Run `wt config approvals add` in a terminal in the project, then try again. No call passes `--yes`.
- A blocking hook that fails, such as `pre-start`, fails the action with wt's message after the worktree is made. Opening the branch again goes to it.
- Locally the action waits for a blocking hook however long it takes. On a remote host the step's time limit applies (see [Errors and limits](#errors-and-limits)).

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
2. The session you ran the action from, if its terminal is inside the checkout. It is renamed and remembered, unless it is already remembered for another checkout that is still there.
3. A new session.

- Sessions are tracked by id, so renaming one is safe.
- Switch Branch never opens a second session for a project.
- A remembered session is only a hint. Closing it by hand, or removing a worktree or switching its branch with git or wt in a terminal, never breaks an action.
- A session remembered for a folder that is gone can still be adopted by another checkout. The old record is kept, across server restarts too, until an action reaches that checkout.
- The script closes only sessions it made. A session it adopted stays open when its checkout goes; the script just forgets it.

## Reviewing a pull request

**Review Pull Request…** needs the [GitHub CLI](https://cli.github.com) on the host that has the project, logged in and on the login shell's `PATH`, with the server's as fallback. Pick a project, then a pull request, or type its number (`123`, `#123`) or paste its link. A typed number or link also opens a closed or merged pull request, unless wt refuses it (see below).

- **The list** comes from `gh pr list`: open pull requests, up to 500, newest first, with those whose review is asked of you or your team first and marked, when `gh` can say which. Each row reads `#123 Title` and `branch · @author · draft · review requested`. A folder icon means it already has a worktree.
- **The checkout** is made by `wt switch pr:<number>`, in the repository `gh repo set-default` names, else the first GitHub remote's. Its branch has the name of the pull request's branch.
  - **From the same repository:** wt fetches the branch every time, and the local branch tracks it, so a fix can be pushed.
  - **From a fork:** the branch fetches from `refs/pull/<number>/head` and pushes to the fork (`branch.<name>.pushRemote`). If a branch of that name exists for something else, wt calls it `<owner>/<branch>`, and that one cannot push.
  - **A branch of that name that is already there**, such as your own, is opened as it is.
  - The session is called `my-app · #123`. A pull request of the main checkout's branch opens in the project's own session.
- **A pasted link** must be to a pull request of the repository wt will look in: the one `gh repo set-default` names, else any remote's (matched by `owner/repo`). Any other link is refused, because wt reads only the number from it.
- **Opening it again** goes to the worktree as it is. To catch up with the pull request, use git there: `git pull`, or after a force push `git fetch` and `git rebase` or `git reset`.
- **Refused by wt:** a pull request whose repository is none of the remotes, one from the same repository whose branch was deleted, such as many merged ones, and one whose fork was deleted. The action shows wt's message.
- The branch remembers its pull request in its git config (`branch.<name>.rex-pr`). Clean Up Branch removes it along with the branch.

## Cleaning up a branch

Pick a project, then a branch. The main checkout's branch is not listed, because it cannot be deleted. The work is done by `wt remove --foreground --delete-branch <branch>`, with `--no-hooks` for a pull request's branch.

1. If the worktree has changed or untracked files, wt refuses, the action shows its message, and nothing is deleted. Ignored files do not count. The action never passes `--force`.
2. The worktree is removed, and the branch is deleted when it adds nothing to the default branch. A squash or rebase merge counts as merged (see `wt remove --help`). A worktree whose folder was deleted by hand is pruned.
3. If wt keeps the branch because it has changes the default branch lacks, you choose **Keep** or **Force delete** (`wt remove -D`). The worktree stays removed either way.
4. Once git no longer lists the worktree, its session is closed, with whatever runs in it, if the script made it. A removal that fails or is stopped after that still closes the session, and the action fails with the reason. So does a worktree whose folder was deleted by hand. A worktree git still lists keeps its session.

On a remote host, a Clean Up step that takes over 10 seconds fails the action while the host carries on. If the worktree is then removed, its session stays open: close it by hand.

## Closing a session from a terminal

To have `wt remove` typed in a terminal close the session the script made for that worktree, put in `~/.config/worktrunk/config.toml`:

```toml
[post-remove]
rex = "rex do close_project_session path={{ worktree_path }}"
```

Clean Up closes its sessions itself, so the hook is optional if you remove worktrees only through Clean Up.

- User hooks need no approval, and wt shell-escapes `{{ worktree_path }}`.
- The hook's `rex do` reaches the server in `REX_SERVER`, which a Rex terminal sets to its own server. With `wt remove` typed outside Rex, it reaches the default server, or fails where none runs.
- It does nothing for a checkout the script has no record of, or whose session the script did not make. An adopted session stays open, and its record is forgotten.
- The path is matched through symbolic links, also after the folder is gone.
- Clean Up of your own branch runs the hook too (a pull request's branch runs none). wt runs it in the background, so Clean Up run from the worktree's own session can have that session closed by the hook before it asks **Keep** or **Force delete**. Otherwise the session is closed once, by whichever comes first.

## Errors and limits

- When git or wt refuses a step, the action fails with its message, on one line, which the app shows as the action's error. Nothing further changes.
- A worktree whose folder was deleted by hand is still on git's list. Opening its branch again shows wt's refusal (`Worktree for <branch> is stale`). Run `git worktree prune` in the project, or clean the branch up.
- Each step on a remote host must answer within 10 seconds. A slower step fails the action, though git or wt may still finish it there.
- To fit, the network calls of a remote step (`git fetch`, `gh`, `wt switch pr:<number>` and every `wt` call that runs hooks) share 8 seconds, and are stopped after that with a message saying so. A worktree that wt made before it was stopped is there when you open the branch again.
- Every other `wt` call on a remote host runs with `GIT_ALLOW_PROTOCOL=none`, so it never asks the remote for the default branch, which can take 10 seconds. wt guesses it from the local branches and records the guess. Run `wt config state default-branch clear` on that host to find it again.
- Commands run through `rex.exec` with argument lists, never a shell, so paths with spaces or quotes are safe.

## Tests

```sh
lua5.1 test/run.lua     # every flow, with a stand-in for Rex, real git and real wt
luajit test/run.lua     # the same on a Mac: brew install luajit (Homebrew has disabled lua@5.1)
rex do test/host.lua    # the real session calls, against a running Rex server
```

Both need `git` and `wt` on `PATH`. `test/run.lua` also needs Perl, to run each command without a terminal as Rex does. It gives wt a config folder of its own and a stand-in for `gh` that serves the pull requests from files. The remotes have `https://github.com/…` addresses that `url.<folder>.insteadOf` takes to local folders, so wt treats them as GitHub repositories.

`test/host.lua` creates a few sessions on the server it runs against and closes them again. It answers the pickers itself and never asks the app to show a session.

Verified on Linux with Git 2.47.3 and wt v0.82.0 (the `aarch64-unknown-linux-musl` release):

- `test/run.lua`: both branch actions, the base step, the default branch from wt, the three ways a session is found, clean-up with wt's refusal and the force offer, wt's hooks for your own branches and none for pull requests, `^` or `-`, a hook that needs approval or fails, a clean-up that wt answers wrongly or that is stopped, pull requests from the same repository and from a fork, the link check, plain folders, and all of these through a stand-in for the app's relay to another host. That includes a remote host whose remote never answers, where finding the default branch stays under 3 seconds.
- By hand, in scratch repositories: wt neither prompts nor blocks without a terminal. It offers no shell integration, and fails at once on a project hook that needs approval, naming the hook's command. User hooks need no approval, and their output goes to stderr, so `--format=json` stays readable.

Verified on macOS with wt from Homebrew (2026-11-21): `test/run.lua`, every test.

Not verified:

- `test/host.lua` against a running Rex server with wt: creating, finding and adopting sessions, and Clean Up closing the sessions it made and leaving adopted ones open. It was updated for wt but not run.
- `wt switch pr:<number>` against GitHub itself, with the real `gh`. Only the stand-in answered, with the fields wt v0.82.0 reads (from its source: `head.ref`, `head.repo`, `base.repo`, `html_url`, `user`, `state`, `draft`, `title`).
- GitHub Enterprise and SSH host aliases for pull requests (wt's `forge.hostname` and `forge.platform` settings).
- The palette section, both keys, and `setup` rebinding or removing them, in a running server's keymap, since `setup` gained its checks and `label` and `layout`.
- The pickers in the Mac app's palette. Only test code answered them.
- A remote host end to end from the Mac app. Only the stand-in covers it.
- What the app shows when the post-remove hook closes the session Clean Up runs in, before it asks **Keep** or **Force delete**.
