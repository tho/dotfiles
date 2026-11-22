-- Runs the script inside Rex's own Lua (gopher-lua), against a real server
-- and real git. It covers what test/run.lua can only stand in for: the
-- session calls, and the ways gopher-lua differs from other Lua 5.1 (a gsub
-- call inside a ".." expression followed by :gmatch once panicked it).
--
-- Run from the repository's top folder:  rex do test/host.lua
--
-- It answers the lists itself and never asks an app to show a session, so
-- nothing appears in the palette and the app stays on its session. It makes
-- a repository in a temporary folder and a few sessions, and removes all of
-- them again, also when a check fails. It needs git and worktrunk (wt) on
-- the server's PATH. It prints "host ok".

-- The answers the lists get, in order, and what was asked and queued.
local answers, asked, queued = {}, {}, {}

-- pick answers a list the way test/run.lua does: a table is typed text, a
-- number is a row's place, a string is a row's title or id.
local function pick(spec)
  asked[#asked + 1] = spec
  local a = table.remove(answers, 1)
  if a == nil then return nil, "cancelled" end
  if type(a) == "table" then return a end
  if type(a) == "number" then return assert(spec.items[a], "no row " .. a).id end
  for _, row in ipairs(spec.items) do
    if row.title == a or row.id == a then return row.id end
  end
  error("no row " .. tostring(a) .. " in " .. spec.title)
end
local function queue(name, args) queued[#queued + 1] = { name, args } end

-- made lists every session this run makes, to close them at the end. The
-- script under test makes sessions too, so every session.create is watched.
local made = {}
local call = rex.call
local function watched_call(method, args)
  local r, err = call(method, args)
  if method == "session.create" and r ~= nil then made[#made + 1] = r.session_id end
  return r, err
end

rex.ui.pick, rex.client.queue, rex.call = pick, queue, watched_call
-- Stop before anything could reach the palette or move the app.
assert(rex.ui.pick == pick and rex.client.queue == queue and rex.call == watched_call,
  "cannot replace rex.ui.pick, rex.client.queue and rex.call in this Rex")

local function exec(...)
  local r = rex.exec({ ... })
  assert(r and r.ok, "failed: " .. table.concat({ ... }, " ") .. "\n" .. tostring(r and r.stderr))
  return (r.stdout:gsub("%s+$", ""))
end
local function git(dir, ...) return exec("git", "-C", dir, ...) end
local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end
local function is_folder(path)
  local r = rex.exec({ "test", "-d", path })
  return r ~= nil and r.ok
end
local function has_branch(dir, name)
  local r = rex.exec({ "git", "-C", dir, "rev-parse", "--verify", "--quiet", "refs/heads/" .. name })
  return r ~= nil and r.ok
end

-- label_of returns the label of a session, or nil when the server has none
-- with that id.
local function label_of(id)
  for _, s in ipairs(call("session.list").sessions or {}) do
    if s.session_id == id then return s.label end
  end
  return nil
end

-- shown returns the session the app was last asked to show.
local function shown()
  local q = queued[#queued]
  assert(q ~= nil and q[1] == "session.select", "the app was asked to show a session")
  return q[2].session_id
end

-- refused runs f, which must end with an error, and returns its message.
local function refused(f, ...)
  local ok, message = pcall(f, ...)
  assert(not ok, "the action was refused")
  return tostring(message)
end

-- by_hand makes a session with a shell in dir, as a person would, and
-- attaches to it, as the app is attached to the session an action runs from.
-- It returns the session's id and the id of its terminal.
local function by_hand(dir)
  local s = assert(rex.call("session.create", {
    label = "rex-projects-host-test",
    initial_windows = { {
      window_label = "shell",
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = { cwd = dir },
      },
    } },
  }))
  local id, block = s.session_id, s.initial_windows[1].block_ids[1]
  assert(call("session.attach", { session_id = id }))
  -- Wait until the terminal says where its shell is.
  for _ = 1, 30 do
    local p = call("block.method", { session_id = id, block_id = block, method = "process" })
    if p and ((p.foreground and p.foreground.cwd) or (p.child and p.child.cwd)) then break end
    rex.sleep(0.1)
  end
  return id, block
end

local dir = (os.getenv("TMPDIR") or "/tmp") .. "/rex-projects-host-" .. os.time()
local here = debug and debug.getinfo and debug.getinfo(1, "S").source:match("^@(.*)/test/[^/]+$") or "."

local function checks()
  exec("mkdir", "-p", dir .. "/repo")
  -- Git and the terminal spell a folder with its symbolic links followed,
  -- and the temporary folder is one on macOS.
  dir = rex.exec({ "pwd", "-P" }, { cwd = dir }).stdout:gsub("%s+$", "")
  local repo = dir .. "/repo"
  git(repo, "init", "-q", "-b", "main")
  write(repo .. "/.gitignore", "build/\n")
  git(repo, "add", ".gitignore")
  git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")

  local P = dofile(here .. "/projects.lua").setup{
    state_file = dir .. "/state.json", worktrees = dir .. "/wt", roots = {},
  }
  local I = P._internal
  local function remembered(folder)
    local record = I.load_state().sessions[folder]
    return record and record.session
  end

  -- The git and folder code, and the state file.
  local trees = I.worktrees(repo)
  assert(#trees == 1 and trees[1].branch == "main", "one checkout on main")
  assert(#I.subfolders(dir) >= 1)
  I.backend.add{ path = repo }
  I.reset()
  assert(I.load_state().projects[1] == repo, "state round trip")
  local rows = I.backend.here_rows{ project = repo }.rows
  assert(#rows == 1 and rows[1].id == "main", "here mode lists the one branch")
  assert(I.backend.here_rows{ project = dir }.plain, "a plain folder has no branches")

  -- Worktree mode: a new name and a base make a worktree and a session.
  answers = { "repo", { text = "feat/x" }, 1 }
  I.worktree_run({})
  local wt = dir .. "/wt/repo/feat-x"
  assert(asked[3].title == "Start feat/x from" and asked[3].items[1].id == "main", "the base step")
  assert(#made == 1, "one session made")
  local first = shown()
  assert(first == made[1] and label_of(first) == "repo · feat/x", tostring(label_of(first)))
  assert(remembered(wt) == first, "remembered by the worktree's folder as git spells it")
  assert(#I.worktrees(repo) == 2 and is_folder(wt))

  -- Find: the worktree's row goes back to the session that was made.
  I.reset()
  answers = { "repo", "feat/x" }
  I.worktree_run({})
  assert(shown() == first and #made == 1, "found, not made again")

  -- Clean-up: ignored files do not keep a worktree, and its session is
  -- closed with it. This run has attached to nothing so far, and the server
  -- refuses calls on a session the caller is not attached to. So closing the
  -- session is all the script's own doing.
  local _, denied = call("session.view", { session_id = first })
  assert(denied ~= nil, "this run is not attached to the worktree's session")
  exec("mkdir", "-p", wt .. "/build")
  write(wt .. "/build/out", "x")
  asked = {}
  answers = { "repo", "feat/x" }
  I.clean_up({})
  assert(#asked == 2, "no offer: " .. asked[#asked].title)
  assert(not is_folder(wt) and not has_branch(repo, "feat/x"), "worktree and branch are gone")
  assert(label_of(first) == nil, "the worktree's session is closed")
  assert(remembered(wt) == nil)

  -- Adopt: a session made by hand in the project becomes the project's own.
  local hand, hand_block = by_hand(repo)
  answers = { "repo", 1 }
  I.switch_run({ session_id = hand, block_id = hand_block })
  assert(shown() == hand and #made == 2, "adopted, and no session made for it")
  assert(label_of(hand) == "repo", "renamed: " .. tostring(label_of(hand)))
  assert(remembered(repo) == hand)

  -- The same in a worktree's folder, with the focused block looked up.
  local wt2 = dir .. "/wt/repo/feat-y"
  git(repo, "worktree", "add", "-q", "-b", "feat/y", wt2, "main")
  local hand2 = by_hand(wt2)
  answers = { "repo", "feat/y" }
  I.worktree_run({ session_id = hand2 })
  assert(shown() == hand2 and #made == 3)
  assert(label_of(hand2) == "repo · feat/y", tostring(label_of(hand2)))

  -- Here mode: a new branch is switched to in the session the project has.
  answers = { "repo", { text = "side branch" }, 1 }
  I.switch_run({})
  assert(git(repo, "symbolic-ref", "--short", "HEAD") == "side-branch")
  assert(shown() == hand and #made == 3, "the one main session")
  -- A branch that lives in a worktree is refused in git's words.
  answers = { "repo", { text = "feat/y" } }
  local message = refused(I.switch_run, {})
  assert(message:find("^fatal: ") and message:find("feat/y", 1, true), message)
  assert(git(repo, "symbolic-ref", "--short", "HEAD") == "side-branch", "nothing switched")
  answers = { "repo", "main" }
  I.switch_run({})
  assert(git(repo, "symbolic-ref", "--short", "HEAD") == "main")

  -- Clean-up: untracked files are refused in wt's words, and nothing changes.
  write(wt2 .. "/new.txt", "x")
  answers = { "repo", "feat/y" }
  message = refused(I.clean_up, {})
  assert(message:find("^Cannot remove worktree: feat/y has uncommitted changes%. "), message)
  assert(is_folder(wt2) and has_branch(repo, "feat/y") and label_of(hand2) ~= nil)

  -- Clean-up: wt keeps a branch with commits of its own, and offers force.
  git(wt2, "add", "new.txt")
  git(wt2, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "work")
  asked = {}
  answers = { "repo", "feat/y", "Force delete" }
  I.clean_up({})
  assert(asked[3].title == "feat/y has changes that the default branch lacks", asked[3].title)
  assert(asked[3].items[1].title == "Keep")
  assert(not is_folder(wt2) and not has_branch(repo, "feat/y"))
  assert(label_of(hand2) == "repo · feat/y", "the adopted session stays open, named")
  assert(remembered(wt2) == nil, "and is forgotten")
  assert(#I.worktrees(repo) == 1)
end

local ok, err = pcall(checks)

-- Close every session this run made, and check that none is left.
for _, id in ipairs(made) do
  if label_of(id) ~= nil then
    call("session.attach", { session_id = id })
    call("session.destroy", { session_id = id })
  end
end
local left = 0
for _, id in ipairs(made) do
  if label_of(id) ~= nil then left = left + 1 end
end
rex.exec({ "rm", "-rf", dir })

if not ok then error(err, 0) end
assert(left == 0, left .. " sessions left behind")
return "host ok"
