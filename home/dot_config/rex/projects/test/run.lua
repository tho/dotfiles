-- Tests for projects.lua against a stand-in for the rex table and real git.
-- Run from the repository's top folder:  lua5.1 test/run.lua
-- Any Lua 5.1 works. It needs git on PATH.

local function sh(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- capture runs a shell command and returns what it printed, its exit status
-- and what it wrote to stderr.
local errfile = os.tmpname()
local function capture(cmd)
  local p = io.popen("{ " .. cmd .. "; } 2>" .. sh(errfile) .. "; echo \"::$?\"")
  local out = p:read("*a"); p:close()
  local body, code = out:match("^(.*)::(%d+)\n$")
  local ef = io.open(errfile); local err = ef:read("*a"); ef:close()
  return body, tonumber(code), err
end

-- A JSON codec just big enough for the state file and for what the backend
-- ops take and answer. It writes a newline inside a string as it is, which
-- real JSON does not, and reads it back the same way.
local json = { null = nil }
function json.encode(v)
  local t = type(v)
  if t == "string" then return '"' .. v:gsub('[\\"]', "\\%0") .. '"' end
  if t ~= "table" then return tostring(v) end
  if #v > 0 or next(v) == nil then
    local parts = {}
    for _, x in ipairs(v) do parts[#parts + 1] = json.encode(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = json.encode(k) .. ":" .. json.encode(x) end
  return "{" .. table.concat(parts, ",") .. "}"
end
function json.decode(s)
  local pos = 1
  local function ws() pos = s:find("%S", pos) or #s + 1 end
  local value
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == '"' then
      local out = {}
      pos = pos + 1
      while s:sub(pos, pos) ~= '"' do
        if s:sub(pos, pos) == "\\" then pos = pos + 1 end
        out[#out + 1] = s:sub(pos, pos); pos = pos + 1
      end
      pos = pos + 1
      return table.concat(out)
    elseif c == "[" then
      local list = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1 return list end
      while true do
        list[#list + 1] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return list end
      end
    elseif c == "{" then
      local obj = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
      while true do
        local k = value(); ws(); pos = pos + 1
        obj[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
      end
    end
    for word, v in pairs({ ["true"] = true, ["false"] = false, null = json.null }) do
      if s:sub(pos, pos + #word - 1) == word then pos = pos + #word; return v end
    end
    local num = s:match("^-?%d+%.?%d*", pos)
    if num then pos = pos + #num; return tonumber(num) end
    error("bad json at " .. pos)
  end
  return value()
end

-- The scripted answers rex.ui gives, in order, and what it was asked.
local answers, asked, actions, calls, queued = {}, {}, {}, {}, {}

-- The key bindings made so far, in order, each as { key = ..., action = ... }.
local bindings = {}
-- bound returns the actions that key is bound to, as one string.
local function bound(key)
  local names = {}
  for _, b in ipairs(bindings) do
    if b.key == key then names[#names + 1] = b.action end
  end
  return table.concat(names, ",")
end

-- relays counts the backend ops sent to another server, and remote_missing
-- makes that server not know the action. in_relay is set while an op runs
-- there, and local_execs counts the commands run outside of one: on the
-- app's own server.
local relays, remote_missing, in_relay, local_execs = 0, false, false, 0

-- The sessions of each stand-in server, by the server's label, "local" for
-- the app's own. cwd is the folder of the session's terminal. attached says
-- whether calls on the session are let through: the real server refuses a
-- call on a session the caller is not attached to, and the app is attached
-- to the session an action is run from.
local stores, made = {}, 0
local function store(host)
  host = host or "local"
  stores[host] = stores[host] or {}
  return stores[host]
end
local function open_session(host, label, cwd)
  made = made + 1
  local s = { session_id = "session:" .. made, block_id = "block:" .. made,
    label = label, cwd = cwd, attached = false }
  local list = store(host)
  list[#list + 1] = s
  return s
end
local function session(host, id)
  for i, s in ipairs(store(host)) do
    if s.session_id == id then return s, i end
  end
end
local function close(host, id)
  local s, at = session(host, id)
  assert(s, "no session " .. tostring(id))
  table.remove(store(host), at)
end

-- api returns the call function of one server: the session methods that
-- projects.lua uses.
local function api(host)
  return function(method, args)
    args = args or {}
    calls[#calls + 1] = { method, args, host }
    if method == "session.list" then
      local list = {}
      for _, s in ipairs(store(host)) do
        list[#list + 1] = { session_id = s.session_id, label = s.label }
      end
      return { sessions = list }
    elseif method == "session.create" then
      local s = open_session(host, args.label, args.initial_windows[1].layout.options.cwd)
      return { session_id = s.session_id, initial_windows = { { block_ids = { s.block_id } } } }
    end
    assert(args.session_id ~= nil, method .. " needs a session id")
    local s, at = session(host, args.session_id)
    if s == nil then return nil, "session_not_found" end
    if method == "session.attach" then
      s.attached = true
      return { view = { label = s.label } }
    end
    if not s.attached then return nil, "conflict: stream is not attached to session " .. s.session_id end
    if method == "session.set_label" then
      s.label = args.label
      return { revision = 1 }
    elseif method == "session.destroy" then
      table.remove(store(host), at)
      return {}
    elseif method == "session.view" then
      return { active_window_id = "window:1",
        windows = { { window_id = "window:1", focused_block_id = s.block_id } } }
    elseif method == "block.method" and args.method == "process" then
      if args.block_id ~= s.block_id then return nil, "not_found" end
      -- child is what the terminal started. On macOS that is login, which
      -- stays in the folder it started in while the shell moves on.
      return { child = { cwd = s.started or s.cwd }, foreground = { cwd = s.cwd } }
    end
    error("stand-in: no method " .. tostring(method))
  end
end

-- A stand-in for the GitHub CLI. prs are the open pull requests, newest
-- first, with the fields gh gives; review_asked holds the numbers whose
-- review is asked of you; gh_missing makes gh not run.
local prs, review_asked, gh_missing, gh_runs = {}, {}, false, 0
local function gh_stub(argv)
  gh_runs = gh_runs + 1
  if gh_missing then return { ok = false, code = 127, stdout = "", stderr = "gh: command not found" } end
  local function answer(v) return { ok = true, code = 0, stdout = json.encode(v), stderr = "" } end
  if argv[2] == "pr" and argv[3] == "list" then
    local searching = false
    for _, a in ipairs(argv) do if a == "--search" then searching = true end end
    local out = {}
    for _, p in ipairs(prs) do
      if not searching or review_asked[p.number] then out[#out + 1] = p end
    end
    return answer(out)
  elseif argv[2] == "pr" and argv[3] == "view" then
    for _, p in ipairs(prs) do
      if tostring(p.number) == argv[4] then return answer(p) end
    end
    return { ok = false, code = 1, stdout = "", stderr = "GraphQL: Could not resolve to a PullRequest with the number of " .. argv[4] .. "." }
  end
  error("gh stand-in: no command " .. table.concat(argv, " "))
end

rex = {
  json = json,
  log = function(level, msg) io.stderr:write("[" .. level .. "] " .. msg .. "\n") end,
  exec = function(argv, opts)
    if not in_relay then local_execs = local_execs + 1 end
    if argv[1] == "gh" then return gh_stub(argv) end
    local parts = {}
    for _, a in ipairs(argv) do parts[#parts + 1] = sh(a) end
    local cmd = table.concat(parts, " ")
    if opts and opts.cwd then cmd = "cd " .. sh(opts.cwd) .. " && " .. cmd end
    local out, code, err = capture(cmd)
    return { ok = code == 0, code = code, stdout = out, stderr = err }
  end,
  action = function(spec) actions[spec.name] = spec end,
  bind = function(key, name) bindings[#bindings + 1] = { key = key, action = name } end,
  -- unbind removes one binding, given as rex.bindings returns it, or every
  -- binding of a key.
  unbind = function(what)
    for i = #bindings, 1, -1 do
      if bindings[i] == what or bindings[i].key == what then table.remove(bindings, i) end
    end
  end,
  bindings = function(filter)
    local list = {}
    for _, b in ipairs(bindings) do
      if filter == nil or filter.action == nil or filter.action == b.action then list[#list + 1] = b end
    end
    return list
  end,
  ui = {
    -- pick checks what the real one raises on, then gives the next answer:
    -- a table is typed text, a number is a row's place in the list, and a
    -- string is a row's title or id. A function is called with the list and
    -- returns the answer, for a test that looks around while a list shows.
    pick = function(spec)
      assert(type(spec.title) == "string" and spec.title ~= "", "a list needs a title")
      assert(#spec.items <= 2000, spec.title .. " has more than 2,000 rows")
      local ids = {}
      for _, row in ipairs(spec.items) do
        assert(not ids[row.id], "two rows with the id " .. tostring(row.id) .. " in " .. spec.title)
        ids[row.id] = true
      end
      asked[#asked + 1] = spec
      local a = table.remove(answers, 1)
      if type(a) == "function" then a = a(spec) end
      if a == nil then return nil, "cancelled" end
      if type(a) == "table" then
        assert(spec.allow_other, spec.title .. " takes no typed text")
        return a
      end
      if type(a) == "number" then return assert(spec.items[a], "no row " .. a).id end
      for _, row in ipairs(spec.items) do
        if row.title == a or row.id == a then return row.id end
      end
      error("no row " .. tostring(a) .. " in " .. spec.title)
    end,
  },
  layout = { block = function(t) return t end },
  call = api(nil),
  -- Another server, as the app relays calls to it: arguments and results go
  -- through JSON, and client.action runs the action this file defined.
  server = function(label)
    local call = api(label)
    return { call = function(method, args)
      if method ~= "client.action" then return call(method, args) end
      if remote_missing then return nil, "not_found: no action " .. args.action end
      relays = relays + 1
      local sent = json.decode(json.encode(args))
      in_relay = true
      local ok, result = pcall(actions[sent.action].run, {}, sent.args)
      in_relay = false
      if not ok then return nil, result end
      return { result = json.decode(json.encode(result)), client_actions = {} }
    end }
  end,
  client = { queue = function(m, a) queued[#queued + 1] = { m, a } end },
}

---------------------------------------------------------------------------
-- The repositories
---------------------------------------------------------------------------

local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. sh(tmp))
-- Git spells a folder with every symbolic link followed, and /tmp is one on
-- macOS. Spell the folder that way from the start, so that paths compare.
tmp = capture("cd " .. sh(tmp) .. " && pwd -P"):gsub("%s+$", "")

-- try runs git in dir and returns what it printed, trimmed, and its status.
local function try(dir, ...)
  local a = { "git", "-C", dir, ... }
  for i, v in ipairs(a) do a[i] = sh(v) end
  local out, code = capture(table.concat(a, " "))
  return (out:gsub("%s+$", "")), code
end
-- git does the same and fails the run when git fails.
local function git(dir, ...)
  local out, code = try(dir, ...)
  assert(code == 0, "git failed: " .. table.concat({ ... }, " "))
  return out
end
local function write(path, text)
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end
local function commit(dir, file, text, message)
  write(dir .. "/" .. file, text)
  git(dir, "add", file)
  git(dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", message)
end
local function exists(path) return select(2, capture("test -e " .. sh(path))) == 0 end
local function branch_of(dir) return git(dir, "symbolic-ref", "--short", "HEAD") end
local function has_branch(dir, name)
  return select(2, try(dir, "rev-parse", "--verify", "--quiet", "refs/heads/" .. name)) == 0
end

-- up is the remote "origin": main, pr-1 one commit ahead of it, and shared.
-- fork is the remote "upstream", with a branch shared of its own. The
-- project is a clone of up with both remotes fetched, and a local branch
-- feature-x.
local up, fork = tmp .. "/remotes/up", tmp .. "/remotes/fork"
local repo, plain = tmp .. "/code/my-app", tmp .. "/plain"
os.execute("mkdir -p " .. sh(up) .. " " .. sh(tmp .. "/code") .. " " .. sh(plain))
git(up, "init", "-q", "-b", "main")
commit(up, ".gitignore", "build/\n", "init")
commit(up, "f", "one\n", "f")
git(up, "branch", "shared")
git(up, "switch", "-q", "-c", "pr-1")
commit(up, "f", "two\n", "pr")
git(up, "switch", "-q", "main")
git(tmp, "clone", "-q", up, fork)
git(fork, "branch", "shared")
git(tmp, "clone", "-q", up, repo)
git(repo, "remote", "add", "upstream", fork)
git(repo, "fetch", "-q", "upstream")
git(repo, "branch", "feature-x")
local wt = tmp .. "/wt/my-app"

package.loaded.projects = nil
local P = dofile("projects.lua").setup{
  worktrees = tmp .. "/wt",
  state_file = tmp .. "/state/projects.json",
  roots = {},
}
local I = P._internal

---------------------------------------------------------------------------
-- Helpers for the tests
---------------------------------------------------------------------------

-- tidy removes what the run made on disk.
local function tidy()
  os.execute("rm -rf " .. sh(tmp))
  os.remove(errfile)
end

local n = 0
local function test(name, fn)
  n = n + 1
  answers, asked, calls, queued = {}, {}, {}, {}
  local ok, err = pcall(fn)
  print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or ("\n     " .. tostring(err))))
  if not ok then
    tidy()
    os.exit(1)
  end
end

-- again clears what a test has seen so far, for a second run in one test.
local function again() asked, calls, queued = {}, {}, {} end

-- selected returns the session the app was last asked to show.
local function selected(host)
  local q = queued[#queued]
  assert(q ~= nil and q[1] == "session.select", "the app was asked to show a session")
  return assert(session(host, q[2].session_id), "the session shown exists")
end

-- created counts the sessions made since the test, or again, began.
local function created()
  local count = 0
  for _, c in ipairs(calls) do
    if c[1] == "session.create" then count = count + 1 end
  end
  return count
end

-- refused runs f, which must end with an error, and returns its message:
-- what the app shows the person when an action is refused.
local function refused(f, ...)
  local ok, message = pcall(f, ...)
  assert(not ok, "the action was refused")
  return tostring(message)
end

-- ids returns the ids of rows, in order, and at maps each id to its place.
local function ids(rows)
  local list, at = {}, {}
  for i, row in ipairs(rows) do list[i] = row.id; at[row.id] = i end
  return list, at
end
local function branches(mode)
  local list, at = ids(I.backend.branches{ project = repo, mode = mode }.rows)
  return list, at
end
local function remembered(dir) return I.load_state().sessions[dir] end

---------------------------------------------------------------------------
-- The palette and the keys
---------------------------------------------------------------------------

test("the Projects section holds the six entries, and the backend sits elsewhere", function()
  local titles = {}
  for _, spec in pairs(actions) do
    if spec.category == "Projects" then titles[#titles + 1] = spec.title end
  end
  table.sort(titles)
  local want = { "Add Project to List…", "Clean Up Branch in Project…", "Open Worktree in Project…",
    "Remove Project from List…", "Review Pull Request…", "Switch Branch in Project…" }
  assert(table.concat(titles, " | ") == table.concat(want, " | "), table.concat(titles, " | "))
  assert(actions.projects_backend.category == "Internal")
end)

test("each mode has its key, and the key runs that mode", function()
  assert(bound("alt+cmd+n") == "switch_project_branch", "here mode on alt+cmd+n")
  assert(bound("ctrl+alt+cmd+n") == "open_project_worktree", "worktree mode on ctrl+alt+cmd+n")
  actions[bound("alt+cmd+n")].run({})
  actions[bound("ctrl+alt+cmd+n")].run({})
  assert(asked[1].title == "Switch branch" and asked[2].title == "Open worktree")
end)

test("setup moves or removes either key and leaves the other", function()
  P.setup{ key = "ctrl+alt+p" }
  assert(bound("alt+cmd+n") == "" and bound("ctrl+alt+p") == "switch_project_branch", "key moves")
  assert(bound("ctrl+alt+cmd+n") == "open_project_worktree", "the other key stays")
  P.setup{ worktree_key = "ctrl+alt+w" }
  assert(bound("ctrl+alt+cmd+n") == "" and bound("ctrl+alt+w") == "open_project_worktree", "worktree key moves")
  assert(bound("ctrl+alt+p") == "switch_project_branch")
  P.setup{ worktree_key = false }
  assert(bound("ctrl+alt+w") == "" and bound("ctrl+alt+p") == "switch_project_branch", "one key removed")
  P.setup{ key = false }
  assert(#bindings == 0, "both keys removed")
  -- What else is on a key stays when ours leaves it.
  rex.bind("ctrl+alt+p", "something_else")
  P.setup{ key = "ctrl+alt+p" }
  assert(bound("ctrl+alt+p") == "something_else,switch_project_branch")
  P.setup{ key = "alt+cmd+n", worktree_key = "ctrl+alt+cmd+n" }
  assert(bound("ctrl+alt+p") == "something_else", "only our binding left the key")
  assert(bound("alt+cmd+n") == "switch_project_branch" and bound("ctrl+alt+cmd+n") == "open_project_worktree")
end)

---------------------------------------------------------------------------
-- The project list
---------------------------------------------------------------------------

test("path helpers", function()
  assert(I.expand("  ~/x  ") == I.slashes(os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/x")
  assert(I.expand('"/a/b"') == "/a/b")
  assert(I.expand("C:\\Users\\me") == "C:/Users/me")
  assert(I.basename("/a/b/") == "b")
end)

test("add a project, then it is listed and kept with its session", function()
  answers = { "Add project…", { text = repo }, 1 }
  I.run({}, "here")
  local s = selected()
  assert(s.cwd == repo and s.label == "my-app", "the main session is named after the project")
  local f = io.open(tmp .. "/state/projects.json"); local text = f:read("*a"); f:close()
  assert(text:find("my-app", 1, true), "state file written: " .. text)
  -- Read the file again: the list and the session id come from it.
  I.reset()
  local rows = I.project_rows()
  assert(rows[1].title == "my-app" and rows[#rows].title == "Add project…")
  assert(remembered(repo) == s.session_id, "the session id is in projects.json")
end)

test("plain folder: both modes go to its one session", function()
  answers = { "Add project…", { text = plain }, "Add plain" }
  I.run({}, "here")
  assert(#asked == 3, "a plain folder has no branch list")
  local s = selected()
  assert(s.cwd == plain and s.label == "plain")
  assert(created() == 1)
  again()
  answers = { "plain" }
  I.run({}, "worktree")
  assert(#asked == 1 and selected() == s and created() == 0, "the same session again")
end)

test("plain folder: clean-up shows what git says about it", function()
  answers = { "plain" }
  local message = refused(I.clean_up, {})
  assert(message:find("^fatal: not a git repository"), message)
  assert(#asked == 1, "no branch list")
end)

test("a typed path that is no folder opens the nearest folder, filtered", function()
  answers = { "Add project…", { text = tmp .. "/code/my-/deeper" } }
  I.run({}, "here")
  local page = asked[3]
  assert(page.items[1].title == "Add code", "the nearest folder: " .. page.items[1].title)
  assert(page.value == "my-", "what was not found is the filter: " .. tostring(page.value))
  assert(created() == 0 and #queued == 0)
  -- A name typed in the browser is inside the folder it shows.
  again()
  answers = { "Add project…", { text = tmp }, { text = "code/my-app" }, 1 }
  I.run({}, "here")
  assert(asked[4].title == "Switch branch in my-app", asked[4].title)
  assert(asked[3].value == nil, "a folder that exists has no filter")
end)

test("a path typed in the project picker opens the browser there", function()
  answers = { { text = tmp .. "/code/my" } }
  I.run({}, "here")
  assert(asked[1].allow_other, "the project picker takes a path")
  assert(asked[2].title == "Add project" and asked[2].value == "my")
  assert(asked[2].items[1].title == "Add code")
  -- A repository is added at once, and the flow moves on to its branches.
  again()
  answers = { { text = repo }, 1 }
  I.run({}, "here")
  assert(asked[2].title == "Switch branch in my-app", asked[2].title)
  assert(selected().cwd == repo)
end)

test("a path with no folder above it is refused", function()
  local r = I.backend.typed({ text = "Q:/nowhere/x" })
  assert(r.why == "not a folder: Q:/nowhere/x", tostring(r.why))
end)

test("the browser lists folders alike, and Return on one adds it", function()
  answers = { "Add project…", { text = tmp .. "/code" } }
  I.run({}, "here")
  local page = asked[3]
  assert(page.allow_other, "typing a path is allowed")
  assert(page.items[1].title == "Add code", "first row adds the folder: " .. page.items[1].title)
  assert(page.items[2].title == "..", "second row goes up")
  local row
  for _, r in ipairs(page.items) do if r.title == "my-app" then row = r end end
  assert(row and row.icon == "folder" and row.detail == nil, "every folder looks alike")
  -- Choose the repository: it is added and the flow moves on to the branch.
  again()
  answers = { "Add project…", { text = tmp .. "/code" }, "my-app", 1 }
  I.run({}, "here")
  assert(asked[4].title == "Switch branch in my-app")
  assert(selected().cwd == repo)
end)

test("Return on a plain folder opens it and .. goes back up", function()
  answers = { "Add project…", { text = tmp }, "code", ".." }
  I.run({}, "here")
  assert(created() == 0)
  -- Page 3 lists tmp, page 4 lists code, page 5 is tmp again after "..".
  assert(asked[4].placeholder:find("code", 1, true))
  assert(asked[5].items[1].title == "Add " .. I.basename(tmp))
end)

test("Add Project to List… adds a folder and opens no session", function()
  os.execute("mkdir -p " .. sh(tmp .. "/code/other"))
  answers = { { text = tmp .. "/code" }, "other", "Add other" }
  actions.add_project.run({})
  local listed = false
  for _, p in ipairs(I.load_state().projects) do
    if p == tmp .. "/code/other" then listed = true end
  end
  assert(listed, "the folder is on the list")
  assert(#calls == 0 and #queued == 0, "no session call, nothing shown")
end)

---------------------------------------------------------------------------
-- Here mode: the project's own folder
---------------------------------------------------------------------------

test("here: the list is the current branch, the other local ones, then the remote ones", function()
  local list, at = branches("here")
  assert(list[1] == "main", "the main checkout's branch is first: " .. list[1])
  assert(at["feature-x"], "a regular branch is listed")
  -- Both remotes have a branch shared, and no local branch has that name.
  assert(at["origin/shared"] and at["upstream/shared"], "one row for each remote")
  assert(at["origin/pr-1"])
  assert(at["feature-x"] < at["origin/pr-1"], "local branches come before remote ones")
  assert(not at["origin/main"] and not at["upstream/main"], "a remote branch with a local one is left out")
  assert(not at["origin/HEAD"], "origin/HEAD is no branch")
end)

test("here: Return on the first row goes to the main session and switches nothing", function()
  local main = remembered(repo)
  answers = { "my-app", 1 }
  I.run({}, "here")
  local first = asked[2].items[1]
  assert(first.id == "main" and first.subtitle == "current branch")
  assert(asked[2].allow_other, "a name can be typed")
  assert(branch_of(repo) == "main")
  assert(selected().session_id == main and created() == 0, "the one main session")
end)

test("here: a detached main checkout has a first row too, and Return switches nothing", function()
  git(repo, "switch", "-q", "--detach")
  local main = remembered(repo)
  answers = { "my-app", 1 }
  I.run({}, "here")
  local first = asked[2].items[1]
  assert(first.id == "HEAD" and first.subtitle == "detached", first.id)
  assert(#asked == 2 and selected().session_id == main and created() == 0)
  assert(select(2, try(repo, "symbolic-ref", "-q", "HEAD")) ~= 0, "still detached")
  git(repo, "switch", "-q", "main")
end)

test("here: a local branch is switched to, in the same session", function()
  local main = remembered(repo)
  answers = { "my-app", "feature-x" }
  I.run({}, "here")
  assert(#asked == 2, "no base for a branch that exists")
  assert(branch_of(repo) == "feature-x")
  assert(selected().session_id == main and created() == 0)
end)

test("here: a remote branch becomes a local one that tracks the remote picked", function()
  answers = { "my-app", "upstream/shared" }
  I.run({}, "here")
  assert(#asked == 2)
  assert(branch_of(repo) == "shared", "the local branch has the plain name")
  assert(git(repo, "rev-parse", "--abbrev-ref", "shared@{upstream}") == "upstream/shared")
  local list, at = branches("here")
  assert(list[1] == "shared" and not at["origin/shared"] and not at["upstream/shared"])
end)

test("here: a new name asks for a base, and a remote base is not tracked", function()
  answers = { "my-app", { text = " feat login " }, "origin/pr-1" }
  I.run({}, "here")
  local bases = asked[3]
  assert(bases.title == "Start feat-login from", "spaces become dashes: " .. bases.title)
  assert(bases.allow_other, "a base can be typed")
  local list, at = ids(bases.items)
  assert(list[1] == "origin/main" and bases.items[1].subtitle == "default · fetched first",
    "the default base is first, as its remote branch: " .. list[1])
  assert(list[2] == "shared", "then the branch the main checkout is on")
  assert(at["feature-x"] and at["main"] and at["upstream/shared"], "then every other branch")
  assert(branch_of(repo) == "feat-login")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/pr-1"), "it starts at the base")
  assert(select(2, try(repo, "config", "--get", "branch.feat-login.remote")) ~= 0, "--no-track")
  assert(selected().session_id == remembered(repo) and created() == 0)
end)

test("here: Return on the base list starts from the default, and a base can be typed", function()
  answers = { "my-app", { text = "from-default" }, 1 }
  I.run({}, "here")
  assert(branch_of(repo) == "from-default")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/main"))
  -- A remote branch is one however it is written.
  answers = { "my-app", { text = "from-long" }, { text = "remotes/origin/pr-1" } }
  I.run({}, "here")
  assert(branch_of(repo) == "from-long")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/pr-1"))
  assert(select(2, try(repo, "config", "--get", "branch.from-long.remote")) ~= 0, "--no-track")
  answers = { "my-app", { text = "from-typed" }, { text = "origin/pr-1" } }
  I.run({}, "here")
  assert(branch_of(repo) == "from-typed")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/pr-1"))
  assert(select(2, try(repo, "config", "--get", "branch.from-typed.remote")) ~= 0, "--no-track")
end)

test("branch_order lists the branches and worktrees by newest commit or by name", function()
  local dir = tmp .. "/code/order"
  os.execute("mkdir -p " .. sh(dir))
  git(dir, "init", "-q", "-b", "main")
  commit(dir, "f", "0\n", "init")
  -- zeta gets the newer commit, and wt-zeta the folder git lists first.
  for i, name in ipairs({ "alpha", "zeta" }) do
    git(dir, "branch", name)
    git(dir, "branch", "wt-" .. name)
    os.execute("cd " .. sh(dir) .. " && git switch -q " .. name ..
      " && GIT_COMMITTER_DATE='2020-01-0" .. i .. "T00:00:00' git -c user.name=t -c user.email=t@t" ..
      " commit -q --allow-empty -m " .. name .. " && git switch -q main")
  end
  git(dir, "worktree", "add", "-q", tmp .. "/order-wt/a", "wt-zeta")
  git(dir, "worktree", "add", "-q", tmp .. "/order-wt/z", "wt-alpha")
  local function rows(mode) return ids(I.backend.branches{ project = dir, mode = mode }.rows) end

  local _, at = rows("worktree")
  assert(at["wt-zeta"] < at["wt-alpha"], "worktrees as git lists them")
  assert(at["zeta"] < at["alpha"], "newest commit first")
  P.setup{ branch_order = "name" }
  _, at = rows("worktree")
  assert(at["wt-alpha"] < at["wt-zeta"], "worktrees by name")
  assert(at["alpha"] < at["zeta"], "branches by name")
  local list = rows("here")
  assert(list[1] == "main", "the current branch stays first")
  P.setup{ branch_order = "sideways" }
  _, at = rows("worktree")
  assert(at["alpha"] < at["zeta"], "an unknown order changes nothing")
  P.setup{ branch_order = "recent" }
  _, at = rows("worktree")
  assert(at["zeta"] < at["alpha"], "back to newest commit first")
end)

test("the default base is a setting, and is left out where it names nothing", function()
  P.setup{ base = "feature-x" }
  local r = I.backend.open{ project = repo, mode = "here", name = "x1" }
  assert(r.name == "x1" and r.bases[1].id == "feature-x" and r.bases[2].id == "from-typed")
  P.setup{ base = "develop" }
  r = I.backend.open{ project = repo, mode = "here", name = "x1" }
  assert(r.bases[1].id == "from-typed", "first is the current branch: " .. r.bases[1].id)
  P.setup{ base = false }
  assert(not has_branch(repo, "x1"), "asking for the bases makes nothing")
end)

test("the default base is fetched first, in both modes, and no other base is", function()
  -- origin's main moves on, and local main has a commit that is not pushed.
  git(repo, "switch", "-q", "main")
  commit(up, "g", "new upstream\n", "upstream moves")
  commit(repo, "h", "local only\n", "not pushed")
  local upstream_main, local_main = git(up, "rev-parse", "main"), git(repo, "rev-parse", "main")
  assert(git(repo, "rev-parse", "origin/main") ~= upstream_main, "not fetched yet")

  answers = { "my-app", { text = "fresh-here" }, 1 }
  I.run({}, "here")
  assert(branch_of(repo) == "fresh-here")
  assert(git(repo, "rev-parse", "HEAD") == upstream_main, "starts from origin/main as it is now")
  assert(select(2, try(repo, "config", "--get", "branch.fresh-here.remote")) ~= 0, "--no-track")
  assert(git(repo, "rev-parse", "main") == local_main, "local main is left alone")

  commit(up, "g", "newer upstream\n", "upstream moves again")
  upstream_main = git(up, "rev-parse", "main")
  answers = { "my-app", { text = "fresh-wt" }, "origin/main" }
  I.run({}, "worktree")
  assert(git(wt .. "/fresh-wt", "rev-parse", "HEAD") == upstream_main, "a worktree fetches too")

  -- Local main, chosen on purpose, is taken as it is, and nothing is fetched.
  commit(up, "g", "newest upstream\n", "upstream moves once more")
  local before = git(repo, "rev-parse", "origin/main")
  git(repo, "switch", "-q", "fresh-here")
  answers = { "my-app", { text = "from-local" }, "main" }
  I.run({}, "worktree")
  assert(git(wt .. "/from-local", "rev-parse", "HEAD") == local_main, "local main, unpushed commit and all")
  assert(git(repo, "rev-parse", "origin/main") == before, "nothing was fetched")

  -- A fetch that fails stops the action with git's message.
  git(repo, "remote", "set-url", "origin", tmp .. "/nowhere")
  answers = { "my-app", { text = "offline" }, 1 }
  local message = refused(I.run, {}, "here")
  git(repo, "remote", "set-url", "origin", up)
  assert(message:find("^fatal:"), message)
  assert(not has_branch(repo, "offline") and branch_of(repo) == "fresh-here", "nothing changed")

  -- A default with no remote branch is listed as it is.
  P.setup{ base = "feature-x" }
  local r = I.backend.open{ project = repo, mode = "here", name = "x2" }
  assert(r.bases[1].id == "feature-x" and r.bases[1].subtitle == "default")
  P.setup{ base = false }
  git(repo, "switch", "-q", "main")
  -- Leave main where origin has it, so that later tests start level.
  git(repo, "fetch", "-q", "origin")
  git(repo, "reset", "-q", "--hard", "origin/main")
  for _, name in ipairs({ "fresh-wt", "from-local" }) do
    git(repo, "worktree", "remove", wt .. "/" .. name)
    git(repo, "branch", "-q", "-D", name)
  end
  git(repo, "branch", "-q", "-D", "fresh-here")
end)

test("unset, the default base is the remote's default branch", function()
  -- A remote whose default branch is trunk, and no main anywhere.
  local up2, clone = tmp .. "/remotes/trunk", tmp .. "/code/trunk-app"
  os.execute("mkdir -p " .. sh(up2))
  git(up2, "init", "-q", "-b", "trunk")
  commit(up2, "f", "0\n", "init")
  git(tmp, "clone", "-q", up2, clone)
  local r = I.backend.open{ project = clone, mode = "here", name = "t1" }
  assert(r.bases[1].id == "origin/trunk" and r.bases[1].subtitle == "default · fetched first",
    "origin's HEAD names the default: " .. r.bases[1].id)
  -- The setting wins over what the remote says.
  git(clone, "branch", "other")
  P.setup{ base = "other" }
  r = I.backend.open{ project = clone, mode = "here", name = "t1" }
  assert(r.bases[1].id == "other" and r.bases[1].subtitle == "default", r.bases[1].id)
  P.setup{ base = false }
  -- With nothing recorded it is main, which this repository lacks, so the
  -- first row is the current branch.
  git(clone, "remote", "set-head", "origin", "-d")
  r = I.backend.open{ project = clone, mode = "here", name = "t1" }
  assert(r.bases[1].id == "trunk" and r.bases[1].subtitle == "current branch", r.bases[1].id)
  -- Another remote's HEAD counts when origin has none.
  git(clone, "remote", "add", "mirror", up2)
  git(clone, "fetch", "-q", "mirror")
  git(clone, "remote", "set-head", "mirror", "trunk")
  r = I.backend.open{ project = clone, mode = "here", name = "t1" }
  assert(r.bases[1].id == "origin/trunk", "trunk, fetched from the remote local trunk follows: " .. r.bases[1].id)
end)

test("here: a name git does not take is refused with git's words, before any base", function()
  answers = { "my-app", { text = "bad..name" } }
  local message = refused(I.run, {}, "here")
  assert(#asked == 2)
  assert(message == "fatal: 'bad..name' is not a valid branch name", message)
  assert(#queued == 0)
end)

test("here: when git refuses to switch, its message is the error and nothing changes", function()
  git(repo, "switch", "-q", "main")
  -- f differs between main and feat-login, so git will not carry the change.
  write(repo .. "/f", "mine\n")
  answers = { "my-app", "feat-login" }
  local message = refused(I.run, {}, "here")
  assert(message:find("^error: Your local changes"), message)
  assert(message:find("Please commit your changes or stash them", 1, true) and not message:find("\n"),
    "the rest of git's message follows on the same line: " .. message)
  assert(branch_of(repo) == "main" and #queued == 0 and created() == 0)
  git(repo, "checkout", "-q", "--", "f")
end)

---------------------------------------------------------------------------
-- Worktree mode
---------------------------------------------------------------------------

test("worktree: a new name plus a base makes the branch, the worktree and its session", function()
  answers = { "my-app", { text = "feat/x" }, 1 }
  I.run({}, "worktree")
  assert(asked[2].title == "Open worktree in my-app" and asked[2].allow_other)
  assert(asked[3].title == "Start feat/x from" and asked[3].items[1].id == "origin/main")
  local s = selected()
  assert(s.cwd == wt .. "/feat-x", "the session opens in the worktree: " .. s.cwd)
  assert(s.label == "my-app · feat/x", s.label)
  assert(created() == 1)
  assert(branch_of(wt .. "/feat-x") == "feat/x")
  assert(branch_of(repo) == "main", "the main checkout stays as it was")
end)

test("worktree: the list is the worktrees, the regular branches, then the remote ones", function()
  local rows = I.backend.branches{ project = repo, mode = "worktree" }.rows
  assert(rows[1].id == "feat/x" and rows[1].icon == "folder", "worktrees are first")
  assert(rows[1].subtitle == I.short(wt .. "/feat-x"))
  local list, at = ids(rows)
  assert(not at["main"], "the main checkout's branch is left off")
  assert(at["feature-x"] and at["origin/pr-1"])
  assert(at["feat/x"] < at["feature-x"] and at["feature-x"] < at["origin/pr-1"])
  local _, here = branches("here")
  assert(not here["feat/x"], "here mode does not list a branch that a worktree holds")
end)

test("worktree: a worktree's row goes back to its session", function()
  local id = remembered(wt .. "/feat-x")
  answers = { "my-app", "feat/x" }
  I.run({}, "worktree")
  assert(#asked == 2)
  assert(selected().session_id == id and created() == 0)
end)

test("worktree: a local branch and a remote branch each get a worktree and a session", function()
  answers = { "my-app", "feature-x" }
  I.run({}, "worktree")
  assert(#asked == 2, "no base for a branch that exists")
  local s = selected()
  assert(s.cwd == wt .. "/feature-x" and s.label == "my-app · feature-x")
  answers = { "my-app", "origin/pr-1" }
  I.run({}, "worktree")
  s = selected()
  assert(s.cwd == wt .. "/pr-1" and s.label == "my-app · pr-1", "the local branch has the plain name")
  assert(git(repo, "rev-parse", "--abbrev-ref", "pr-1@{upstream}") == "origin/pr-1")
  assert(created() == 2)
end)

test("worktree: a new branch from a remote base is not tracked", function()
  answers = { "my-app", { text = "topic" }, "origin/main" }
  I.run({}, "worktree")
  assert(branch_of(wt .. "/topic") == "topic")
  assert(select(2, try(repo, "config", "--get", "branch.topic.remote")) ~= 0, "--no-track")
end)

test("worktree: when git refuses, its message is the error and no session is made", function()
  -- The main checkout's branch is not on the list, but it can be typed.
  answers = { "my-app", { text = "main" } }
  local title = refused(I.run, {}, "worktree")
  assert(title:find("^fatal: ") and title:find("'main'", 1, true), "git's reason leads: " .. title)
  assert(created() == 0 and #queued == 0)
  assert(not exists(wt .. "/main"))
end)

test("worktree: a revision such as main~1 is no branch, and makes no worktree", function()
  local before = #I.worktrees(repo)
  answers = { "my-app", { text = "main~1" } }
  local title = refused(I.run, {}, "worktree")
  assert(#asked == 2, "project, then name: no base is asked for")
  assert(title:find("^fatal: ") and title:find("'main~1'", 1, true), "git's refusal: " .. title)
  assert(created() == 0 and #queued == 0, "no session")
  assert(#I.worktrees(repo) == before and not exists(wt .. "/main~1"), "no worktree")
end)

test("here: a typed branch that lives in a worktree shows git's refusal", function()
  answers = { "my-app", { text = "feat/x" } }
  local title = refused(I.run, {}, "here")
  assert(title:find("^fatal: ") and title:find("'feat/x'", 1, true) and title:find("worktree", 1, true), title)
  assert(branch_of(repo) == "main" and #queued == 0, "nothing switched")
end)

---------------------------------------------------------------------------
-- Finding a checkout's session
---------------------------------------------------------------------------

test("lookup: a remembered session that is gone is replaced by a new one", function()
  local old = remembered(repo)
  close(nil, old)
  answers = { "my-app", 1 }
  I.run({}, "here")
  local s = selected()
  assert(s.session_id ~= old and created() == 1)
  assert(remembered(repo) == s.session_id, "the stale id is replaced")
end)

test("lookup: the session the action ran from is adopted when its terminal is inside", function()
  close(nil, remembered(repo))
  os.execute("mkdir -p " .. sh(repo .. "/src"))
  local mine = open_session(nil, "quiet-meadow", repo .. "/src")
  -- The shell was started somewhere else and has changed folder since.
  mine.attached, mine.started = true, plain
  answers = { "my-app", 1 }
  I.run({ session_id = mine.session_id, block_id = mine.block_id }, "here")
  assert(created() == 0, "no new session")
  assert(mine.label == "my-app", "it is renamed: " .. mine.label)
  assert(selected() == mine and remembered(repo) == mine.session_id)
end)

test("lookup: a hand-made session in a worktree folder becomes that worktree's session", function()
  close(nil, remembered(wt .. "/feat-x"))
  local mine = open_session(nil, "calm-river", wt .. "/feat-x")
  mine.attached = true
  answers = { "my-app", "feat/x" }
  -- Without a block id, the session's focused block is asked.
  I.run({ session_id = mine.session_id }, "worktree")
  assert(created() == 0 and mine.label == "my-app · feat/x", mine.label)
  assert(selected() == mine and remembered(wt .. "/feat-x") == mine.session_id)
end)

test("lookup: a remembered session that lives wins over the one the action ran from", function()
  local main = remembered(repo)
  local other = open_session(nil, "other", repo)
  other.attached = true
  answers = { "my-app", 1 }
  I.run({ session_id = other.session_id, block_id = other.block_id }, "here")
  assert(selected().session_id == main and created() == 0)
  assert(other.label == "other", "the other session keeps its name")
  close(nil, other.session_id)
end)

test("lookup: a session remembered for another checkout is not adopted", function()
  -- The worktree's session has its terminal in the main checkout now, and
  -- the main checkout's session is gone.
  local theirs = session(nil, remembered(wt .. "/feat-x"))
  theirs.cwd = repo
  close(nil, remembered(repo))
  answers = { "my-app", 1 }
  I.run({ session_id = theirs.session_id, block_id = theirs.block_id }, "here")
  assert(created() == 1 and selected() ~= theirs)
  assert(theirs.label == "my-app · feat/x" and remembered(wt .. "/feat-x") == theirs.session_id)
  theirs.cwd = wt .. "/feat-x"
end)

test("lookup: a terminal that is somewhere else gets a new session", function()
  close(nil, remembered(repo))
  local mine = open_session(nil, "elsewhere", plain)
  mine.attached = true
  answers = { "my-app", 1 }
  I.run({ session_id = mine.session_id, block_id = mine.block_id }, "here")
  assert(created() == 1 and selected() ~= mine and mine.label == "elsewhere")
  close(nil, mine.session_id)
end)

---------------------------------------------------------------------------
-- Clean-up
---------------------------------------------------------------------------

test("clean-up: the list is the worktrees and the regular branches, without the current one", function()
  local rows = I.backend.branches{ project = repo, mode = "cleanup" }.rows
  local list, at = ids(rows)
  assert(rows[1].icon == "folder", "worktrees are first")
  assert(at["feat/x"] and at["shared"], "branches with and without a worktree")
  assert(not at["main"], "the main checkout's branch is left off")
  for _, id in ipairs(list) do
    assert(not id:find("^origin/") and not id:find("^upstream/"), "no remote branch: " .. id)
  end
  answers = { "my-app" }
  I.clean_up({})
  assert(asked[2].title == "Clean up branch in my-app" and not asked[2].allow_other)
end)

test("clean-up: a worktree with only ignored files goes, with its branch and its session", function()
  local dir = wt .. "/feature-x"
  -- build/ is in .gitignore.
  os.execute("mkdir -p " .. sh(dir .. "/build"))
  write(dir .. "/build/out", "x")
  local id = remembered(dir)
  assert(session(nil, id) and not session(nil, id).attached, "a session the action is not attached to")
  answers = { "my-app", "feature-x" }
  I.clean_up({})
  assert(#asked == 2, "no offer: " .. asked[#asked].title)
  assert(not exists(dir), "the worktree is removed")
  assert(not has_branch(repo, "feature-x"), "the branch is deleted")
  assert(session(nil, id) == nil, "the worktree's session is closed")
  assert(remembered(dir) == nil)
  assert(calls[#calls][1] == "session.destroy" and calls[#calls - 1][1] == "session.attach",
    "attach, then destroy, last of all")
end)

test("clean-up: uncommitted changes are refused and nothing changes", function()
  local dir = wt .. "/pr-1"
  local id = remembered(dir)
  write(dir .. "/new.txt", "x")
  answers = { "my-app", "pr-1" }
  local message = refused(I.clean_up, {})
  assert(message == "Nothing was deleted: the worktree of pr-1 has uncommitted changes. Commit or discard them, then clean up again.", message)
  assert(exists(dir .. "/new.txt") and has_branch(repo, "pr-1") and session(nil, id), "an untracked file")
  os.remove(dir .. "/new.txt")
  write(dir .. "/f", "changed\n")
  again()
  answers = { "my-app", "pr-1" }
  assert(refused(I.clean_up, {}) == "Nothing was deleted: the worktree of pr-1 has uncommitted changes. Commit or discard them, then clean up again.")
  assert(exists(dir) and has_branch(repo, "pr-1") and session(nil, id), "a modified file")
  assert(remembered(dir) == id)
  assert(#calls == 0, "the session is left alone")
  git(dir, "checkout", "-q", "--", "f")
end)

test("clean-up: untracked files count even when git status is set to hide them", function()
  local dir = wt .. "/pr-1"
  local id = remembered(dir)
  git(repo, "config", "status.showUntrackedFiles", "no")
  write(dir .. "/new.txt", "x")
  answers = { "my-app", "pr-1" }
  local message = refused(I.clean_up, {})
  git(repo, "config", "--unset", "status.showUntrackedFiles")
  assert(message == "Nothing was deleted: the worktree of pr-1 has uncommitted changes. Commit or discard them, then clean up again.", message)
  assert(exists(dir .. "/new.txt") and has_branch(repo, "pr-1") and session(nil, id), "nothing changed")
  os.remove(dir .. "/new.txt")
end)

test("clean-up: when git keeps the branch, its reason is the offer, and Keep keeps it", function()
  local dir = wt .. "/feat-x"
  commit(dir, "g", "work\n", "work")
  local id = remembered(dir)
  answers = { "my-app", "feat/x", function()
    -- The action may be running in that session, so it has to last until
    -- nothing more is asked.
    assert(session(nil, id), "the session is open while the offer shows")
    return "Keep"
  end }
  I.clean_up({})
  local offer = asked[3]
  assert(offer.title:find("^error: ") and offer.title:find("not fully merged", 1, true), offer.title)
  assert(#offer.items == 2 and offer.items[1].title == "Keep", "Keep is first")
  assert(not exists(dir), "the worktree stays removed")
  assert(has_branch(repo, "feat/x"), "the branch and its commits stay")
  assert(session(nil, id) == nil, "the worktree's session is closed")
  assert(calls[#calls][1] == "session.destroy")
end)

test("clean-up: accepting the offer deletes the branch with -D", function()
  local _, at = branches("cleanup")
  assert(at["feat/x"], "the branch is a regular one now")
  answers = { "my-app", "feat/x" }
  I.clean_up({})
  assert(has_branch(repo, "feat/x"), "closing the offer keeps the branch")
  again()
  answers = { "my-app", "feat/x", "Force delete" }
  I.clean_up({})
  assert(#asked == 3, "nothing after the offer")
  assert(not has_branch(repo, "feat/x"))
  assert(#calls == 0, "a branch without a worktree has no session to close")
end)

test("clean-up: a worktree whose folder is gone is cleared with its branch", function()
  local dir = wt .. "/topic"
  os.execute("rm -rf " .. sh(dir))
  local _, at = branches("worktree")
  assert(not at["topic"], "it is no place to open a session")
  local _, here = branches("here")
  assert(not here["topic"], "and git still counts its branch as held")
  answers = { "my-app", "topic" }
  I.clean_up({})
  assert(#asked == 2 and not has_branch(repo, "topic"))
  assert(#I.worktrees(repo) == 2, "the main checkout and pr-1 are left")
end)

---------------------------------------------------------------------------
-- What rex.ui.pick raises on
---------------------------------------------------------------------------

test("a list never has two rows with one id, or more than 2,000 rows", function()
  local big = tmp .. "/code/big"
  os.execute("mkdir -p " .. sh(big))
  git(big, "init", "-q", "-b", "main")
  git(big, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
  git(big, "remote", "add", "origin", up)
  local head = git(big, "rev-parse", "HEAD")
  local lines = {}
  for i = 1, 2100 do
    lines[i] = "create refs/remotes/origin/b" .. string.format("%04d", i) .. " " .. head
  end
  -- A local branch and a remote one that are written the same.
  lines[#lines + 1] = "create refs/heads/origin/b0001 " .. head
  write(tmp .. "/refs.txt", table.concat(lines, "\n") .. "\n")
  local _, code = capture("git -C " .. sh(big) .. " update-ref --stdin < " .. sh(tmp .. "/refs.txt"))
  assert(code == 0, "refs made")
  local rows = I.backend.branches{ project = big, mode = "here" }.rows
  assert(#rows == 2000, "rows: " .. #rows)
  local list, at = ids(rows)
  assert(list[1] == "main" and at["origin/b0001"] == 2, "the local branch origin/b0001 is listed once")
  local seen = {}
  for _, id in ipairs(list) do assert(not seen[id], id); seen[id] = true end
  assert(#I.backend.open{ project = big, mode = "here", name = "new" }.bases == 2000)
  -- A branch that fell off the end of the list can still be typed.
  assert(not at["origin/b2100"])
  local r = I.backend.open{ project = big, mode = "here", name = "origin/b2100" }
  assert(r.dir == big and branch_of(big) == "b2100", tostring(r.why))
end)

---------------------------------------------------------------------------
-- Review Pull Request
---------------------------------------------------------------------------

-- The pull requests live in up as refs/pull/<n>/head, as on GitHub. #9 is a
-- branch of up, review-me; #8 comes from the fork's branch fork-fix. gh
-- names up as https://github.com/remotes/up, which matches the remote by
-- its last two folders.
local function publish(n, ref)
  git(up, "update-ref", "refs/pull/" .. n .. "/head", ref)
  for _, p in ipairs(prs) do
    if p.number == n then p.headRefOid = git(up, "rev-parse", ref) end
  end
end
local function pull(n, title, head, cross, author)
  return { number = n, title = title, headRefName = head, isCrossRepository = cross,
    isDraft = false, author = { login = author }, url = "https://github.com/remotes/up/pull/" .. n }
end
local review_dir = wt .. "/review-me"

test("review: the list puts the reviews asked of you first, then the rest", function()
  git(up, "switch", "-q", "-c", "review-me")
  commit(up, "r", "one\n", "review one")
  git(up, "switch", "-q", "main")
  git(fork, "switch", "-q", "-c", "fork-fix")
  commit(fork, "k", "fork\n", "fork fix")
  git(up, "fetch", "-q", fork, "fork-fix:refs/pull/8/head")
  prs = { pull(9, "Review me", "review-me", false, "ana"), pull(8, "Fix from a fork", "fork-fix", true, "bo") }
  prs[2].isDraft = true
  publish(9, "review-me")
  prs[2].headRefOid = git(up, "rev-parse", "refs/pull/8/head")
  review_asked = { [8] = true }

  answers = { "my-app", nil }
  I.review_run({})
  assert(asked[1].title == "Review pull request", asked[1].title)
  local list = asked[2]
  assert(list.title == "Review pull request in my-app" and list.allow_other)
  assert(list.items[1].id == "#8" and list.items[2].id == "#9", "asked of you first")
  assert(list.items[1].title == "#8 Fix from a fork", list.items[1].title)
  assert(list.items[1].subtitle == "fork-fix · @bo · draft · review requested", list.items[1].subtitle)
  assert(list.items[2].subtitle == "review-me · @ana" and list.items[2].icon == "branch")
end)

test("review: a pull request of the repository gets its branch, a worktree and a session", function()
  answers = { "my-app", "#9" }
  I.review_run({})
  local s = selected()
  assert(s.cwd == review_dir and s.label == "my-app · #9", s.label)
  assert(branch_of(review_dir) == "review-me")
  assert(git(review_dir, "rev-parse", "HEAD") == git(up, "rev-parse", "review-me"))
  assert(git(repo, "rev-parse", "--abbrev-ref", "review-me@{upstream}") == "origin/review-me", "it follows the remote branch")
  assert(git(repo, "config", "--get", "branch.review-me.rex-pr") == "9")
  -- Again: the same session, nothing asked, and the row shows the worktree.
  again()
  answers = { "my-app", "#9" }
  I.review_run({})
  assert(#asked == 2 and selected() == s and created() == 0)
  local _, at = ids(asked[2].items)
  assert(asked[2].items[at["#9"]].icon == "folder")
end)

test("review: a pull request from a fork is pr/<number>, and follows nothing", function()
  answers = { "my-app", { text = "https://github.com/remotes/up/pull/8" } }
  I.review_run({})
  local s = selected()
  assert(s.cwd == wt .. "/pr-8" and s.label == "my-app · #8")
  assert(branch_of(wt .. "/pr-8") == "pr/8")
  assert(git(wt .. "/pr-8", "rev-parse", "HEAD") == git(fork, "rev-parse", "fork-fix"))
  assert(select(2, try(repo, "config", "--get", "branch.pr/8.remote")) ~= 0)
end)

test("review: new commits ask first, Update fast-forwards, Keep leaves it", function()
  git(up, "switch", "-q", "review-me")
  commit(up, "r", "two\n", "review two")
  git(up, "switch", "-q", "main")
  publish(9, "review-me")
  local before = git(review_dir, "rev-parse", "HEAD")

  answers = { "my-app", "#9", "Keep as is" }
  I.review_run({})
  local dialog = asked[3]
  assert(dialog.title == "#9 has 1 new commit", dialog.title)
  assert(dialog.items[1].title == "Update" and dialog.items[1].subtitle:find("^Fast%-forward to "))
  assert(dialog.items[2].subtitle == "Stay at " .. before:sub(1, 7), dialog.items[2].subtitle)
  assert(git(review_dir, "rev-parse", "HEAD") == before and selected().cwd == review_dir)

  -- No answer keeps it too, and the next time asks again.
  again()
  answers = { "my-app", "#9", nil }
  I.review_run({})
  assert(#asked == 3 and git(review_dir, "rev-parse", "HEAD") == before and selected().cwd == review_dir)

  again()
  answers = { "my-app", "#9", "Update" }
  I.review_run({})
  assert(git(review_dir, "rev-parse", "HEAD") == git(up, "rev-parse", "review-me"))
  again()
  answers = { "my-app", "#9" }
  I.review_run({})
  assert(#asked == 2, "up to date: nothing to ask")
end)

test("review: your commits and changes go on top, also after a force push", function()
  commit(review_dir, "mine", "try\n", "trying something")
  write(review_dir .. "/scratch", "wip\n")
  git(review_dir, "add", "scratch")
  -- The author rewrites the pull request.
  git(up, "switch", "-q", "review-me")
  git(up, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--amend", "-m", "review two, amended")
  git(up, "switch", "-q", "main")
  publish(9, "review-me")

  answers = { "my-app", "#9", "Update" }
  I.review_run({})
  assert(asked[3].title == "#9 was force-pushed", asked[3].title)
  assert(asked[3].items[1].subtitle == "Rebase your 1 commit onto them, keeping your uncommitted changes",
    asked[3].items[1].subtitle)
  assert(git(review_dir, "rev-parse", "HEAD^") == git(up, "rev-parse", "review-me"), "the new head, then your commit")
  assert(git(review_dir, "log", "-1", "--format=%s") == "trying something")
  assert(git(review_dir, "status", "--porcelain") == "A  scratch", "the change is back")
  git(review_dir, "reset", "-q", "--hard", "HEAD^")
end)

test("review: a rebase that stops is undone, and the session is still shown", function()
  commit(review_dir, "r", "mine\n", "my take on r")
  git(up, "switch", "-q", "review-me")
  commit(up, "r", "theirs\n", "their take on r")
  git(up, "switch", "-q", "main")
  publish(9, "review-me")
  local before = git(review_dir, "rev-parse", "HEAD")

  answers = { "my-app", "#9", "Update" }
  local message = refused(I.review_run, {})
  assert(message:find("^#9 was not updated"), message)
  assert(git(review_dir, "rev-parse", "HEAD") == before and git(review_dir, "status", "--porcelain") == "")
  assert(not exists(git(review_dir, "rev-parse", "--git-path", "rebase-merge")), "no rebase is left going")
  assert(selected().cwd == review_dir, "the session was shown before the error")
  -- Keep it at the pull request, without the commit that clashed.
  git(review_dir, "reset", "-q", "--hard", "HEAD^")
  again()
  answers = { "my-app", "#9", "Update" }
  I.review_run({})
  assert(git(review_dir, "rev-parse", "HEAD") == git(up, "rev-parse", "review-me"))
end)

test("review: a branch Review did not make is opened as it is", function()
  -- shared is a branch of the repository already, so #10 opens it.
  table.insert(prs, 1, pull(10, "Shared work", "shared", false, "cy"))
  publish(10, "shared")
  answers = { "my-app", { text = "10" } }
  I.review_run({})
  assert(select(2, try(repo, "config", "--get", "branch.shared.rex-pr")) ~= 0, "not marked")
  assert(#asked == 2)
  table.remove(prs, 1)
end)

test("review: what cannot be reviewed says why", function()
  answers = { "my-app", { text = "not-a-number" } }
  assert(refused(I.review_run, {}) == "not a pull request: not-a-number")
  answers = { "my-app", { text = "77" } }
  assert(refused(I.review_run, {}):find("Could not resolve", 1, true))
  answers = { "plain" }
  assert(refused(I.review_run, {}):find("^fatal: not a git repository"))
  local saved = prs; prs = {}
  answers = { "my-app" }
  assert(refused(I.review_run, {}) == "my-app has no open pull request")
  prs = saved
  gh_missing = true
  answers = { "my-app" }
  local message = refused(I.review_run, {})
  gh_missing = false
  assert(message:find("needs the GitHub CLI", 1, true), message)
  assert(I.pr_number("#12") == 12 and I.pr_number("https://github.com/o/r/pull/12/files") == 12)
  local r = I.repo_of("git@GitHub.com:Acme/App.git")
  assert(r.host == "github.com" and r.path == "acme/app")
  r = I.repo_of("ssh://git@github.com:22/acme/app")
  assert(r.host == "github.com" and r.path == "acme/app")
  assert(I.repo_of("https://github.com/acme/app/").path == "acme/app")
end)

test("review: on another host gh and git run there", function()
  relays, local_execs = 0, 0
  answers = { "my-app", "#8" }
  I.review_run({ server = "studio" })
  assert(local_execs == 0 and relays >= 3)
  assert(asked[1].title == "Review pull request on studio")
end)

test("review: clean-up removes a reviewed branch with its worktree and its marks", function()
  for _, name in ipairs({ "review-me", "pr/8" }) do
    answers = { "my-app", name, "Force delete" }
    I.clean_up({})
    assert(not has_branch(repo, name), name)
    assert(select(2, try(repo, "config", "--get", "branch." .. name .. ".rex-pr")) ~= 0, "the marks go with it")
  end
end)

---------------------------------------------------------------------------
-- A session on another host
---------------------------------------------------------------------------

test("another host: every git and folder step runs there, and so do the session calls", function()
  relays, local_execs = 0, 0
  local here = #store()
  local mine = open_session("studio", "quiet-meadow", plain)
  mine.attached = true
  answers = { "my-app", { text = "feat/remote" }, 1 }
  I.run({ server = "studio", session_id = mine.session_id, block_id = mine.block_id }, "worktree")
  assert(local_execs == 0, "commands run on the app's own server: " .. local_execs)
  assert(relays >= 5, "ops went through the other server: " .. relays)
  assert(asked[1].title == "Open worktree on studio")
  assert(asked[3].title == "Start feat/remote from" and asked[3].items[1].id == "origin/main")
  -- The app is not asked to show a session on another host; see session_for.
  local s = assert(session("studio", remembered(wt .. "/feat-remote")), "remembered on the host")
  assert(s.cwd == wt .. "/feat-remote" and s.label == "my-app · feat/remote")
  assert(#queued == 0 and #store() == here, "no session on the app's own server")
  for _, c in ipairs(calls) do assert(c[3] == "studio", c[1] .. " went to the app's own server") end
end)

test("another host: the session the action ran from is adopted there", function()
  relays, local_execs = 0, 0
  local mine = open_session("studio", "calm-river", repo)
  mine.attached = true
  answers = { "my-app", 1 }
  I.run({ server = "studio", session_id = mine.session_id, block_id = mine.block_id }, "here")
  assert(local_execs == 0 and created() == 0)
  assert(mine.label == "my-app" and remembered(repo) == mine.session_id and #queued == 0)
end)

test("another host: git's refusal arrives as git wrote it", function()
  relays, local_execs = 0, 0
  write(repo .. "/f", "mine\n")
  answers = { "my-app", "feat-login" }
  local message = refused(I.run, { server = "studio" }, "here")
  assert(message:find("^error: Your local changes"), message)
  assert(message:find("Please commit your changes or stash them", 1, true))
  assert(local_execs == 0 and #queued == 0)
  git(repo, "checkout", "-q", "--", "f")
end)

test("another host: clean-up removes the worktree there and closes its session there", function()
  relays, local_execs = 0, 0
  local dir = wt .. "/feat-remote"
  local id = remembered(dir)
  answers = { "my-app", "feat/remote" }
  I.clean_up({ server = "studio" })
  assert(local_execs == 0, "commands run on the app's own server: " .. local_execs)
  assert(asked[1].title == "Clean up branch on studio" and #asked == 2)
  assert(not exists(dir) and not has_branch(repo, "feat/remote"))
  assert(session("studio", id) == nil, "the session is closed on the host")
  for _, c in ipairs(calls) do assert(c[3] == "studio", c[1] .. " went to the app's own server") end
end)

test("a host without this file says so", function()
  remote_missing = true
  local ok, err = pcall(I.run, { server = "studio" }, "here")
  remote_missing = false
  assert(not ok and err:find("init.lua on studio", 1, true), tostring(err))
end)

test("another host: projects are added and removed there", function()
  relays, local_execs = 0, 0
  os.execute("mkdir -p " .. sh(tmp .. "/code/third"))
  answers = { { text = tmp .. "/code" }, "third", "Add third" }
  actions.add_project.run({ server = "studio" })
  local listed = false
  for _, p in ipairs(I.load_state().projects) do
    if p == tmp .. "/code/third" then listed = true end
  end
  assert(listed, "the folder is on the host's list")
  answers = { "plain" }
  I.remove_run({ server = "studio" })
  for _, p in ipairs(I.load_state().projects) do assert(I.basename(p) ~= "plain") end
  assert(remembered(plain) == nil, "its session is forgotten with it")
  assert(local_execs == 0 and relays >= 5, "the folders were read on the host")
end)

test("the shell setting is the shell of a new session", function()
  local function made_with()
    for i = #calls, 1, -1 do
      if calls[i][1] == "session.create" then return calls[i][2].initial_windows[1].layout.options end
    end
  end
  P.setup{ shell = "fish" }
  answers = { "my-app", { text = "shell-one" }, 1 }
  I.run({}, "worktree")
  assert(made_with().shell == "fish" and made_with().cwd == wt .. "/shell-one")
  -- false is the account's default shell again.
  again()
  P.setup{ shell = false }
  answers = { "my-app", { text = "shell-two" }, 1 }
  I.run({}, "worktree")
  assert(made_with().shell == nil and made_with().cwd == wt .. "/shell-two")
end)

---------------------------------------------------------------------------
-- The state file
---------------------------------------------------------------------------

test("the project picker lists the last opened project first, the rest by name", function()
  local scratch = tmp .. "/code/aaa-never"
  os.execute("mkdir -p " .. sh(scratch))
  I.backend.add{ path = scratch }
  I.backend.add{ path = plain }
  I.load_state().recent = {}
  local function top() return ids(I.project_rows())[1] end
  local function landed(r) assert(r.dir ~= nil, "the open landed: " .. tostring(r.why)) end

  -- Switch Branch in a repository, after a plain folder.
  landed(I.backend.open{ project = plain, mode = "worktree" })
  landed(I.backend.open{ project = repo, mode = "here", name = "main" })
  local rows = I.project_rows()
  local _, at = ids(rows)
  assert(at[repo] == 1 and at[plain] == 2, "the last opened first, then the one before")
  -- The rest, never opened, by name.
  assert(#rows > 4, "more than two projects are listed")
  for i = 4, #rows - 1 do
    assert(rows[i - 1].title:lower() <= rows[i].title:lower(), "never opened, by name: " .. rows[i].title)
  end
  assert(rows[3].id == scratch and rows[#rows].id == ":add")

  -- A refusal, or a new name that still needs a base, is no use.
  landed(I.backend.open{ project = plain, mode = "here" })
  assert(I.backend.open{ project = repo, mode = "here", name = "" }.why ~= nil)
  assert(I.backend.open{ project = repo, mode = "here", name = "mru-new" }.bases ~= nil)
  assert(top() == plain, "neither changes the order")

  -- A new worktree counts, and so does going back to it.
  landed(I.backend.open{ project = repo, mode = "worktree", name = "mru-wt", base = "main" })
  assert(top() == repo, "a new worktree")
  landed(I.backend.open{ project = plain, mode = "here" })
  landed(I.backend.open{ project = repo, mode = "worktree", name = "mru-wt" })
  assert(top() == repo, "an existing worktree")

  -- The order outlives a restart.
  I.reset()
  _, at = ids(I.project_rows())
  assert(at[repo] == 1 and at[plain] == 2, "the order is read back from projects.json")

  -- project_order = "name" ignores the order of use, and "recent" brings it back.
  P.setup{ project_order = "name" }
  rows = I.project_rows()
  for i = 2, #rows - 1 do
    assert(rows[i - 1].title:lower() <= rows[i].title:lower(), "all by name: " .. rows[i].title)
  end
  P.setup{ project_order = "sideways" }
  assert(ids(I.project_rows())[1] == rows[1].id, "an unknown order changes nothing")
  P.setup{ project_order = "recent" }
  _, at = ids(I.project_rows())
  assert(at[repo] == 1 and at[plain] == 2, "back to the order of use")

  -- A forgotten project leaves the recent list.
  I.backend.forget{ project = repo }
  for _, p in ipairs(I.load_state().recent) do assert(p ~= repo, "repo left the recent list") end
  assert(I.load_state().recent[1] == plain)
  I.backend.add{ path = repo }
  I.backend.forget{ project = scratch }
end)

test("the project the action ran from is listed first, then the order of use", function()
  local inner = tmp .. "/code/inner"
  os.execute("mkdir -p " .. sh(plain .. "/sub") .. " " .. sh(inner))
  I.backend.add{ path = inner }
  I.load_state().recent = { plain, inner }
  local function order(cwd) return ids(I.project_rows(cwd)) end

  local list = order(nil)
  assert(list[1] == plain and list[2] == inner, "without a terminal, the order of use")
  list = order(repo)
  assert(list[1] == repo and list[2] == plain and list[3] == inner, "the main checkout, then the order of use")
  list = order(repo .. "/src")
  assert(list[1] == repo, "a folder inside the checkout")
  list = order(wt .. "/mru-wt")
  assert(list[1] == repo, "a worktree belongs to its project")
  list = order(plain .. "/sub")
  assert(list[1] == plain and list[2] == inner, "a plain folder goes by its path")
  list = order(tmp .. "/code")
  assert(list[1] == plain and list[2] == inner, "a folder in no project changes nothing")

  -- With project_order "name" it still goes first, and the rest by name.
  P.setup{ project_order = "name" }
  local rows = I.project_rows(wt .. "/mru-wt")
  assert(rows[1].id == repo, "first under name order too")
  for i = 3, #rows - 1 do
    assert(rows[i - 1].title:lower() <= rows[i].title:lower(), "the rest by name: " .. rows[i].title)
  end
  P.setup{ project_order = "recent" }

  -- Through the action: the terminal's folder decides, and any project can
  -- still be chosen.
  local mine = open_session(nil, "here", wt .. "/mru-wt")
  mine.attached = true
  answers = { "plain" }
  I.run({ session_id = mine.session_id, block_id = mine.block_id }, "here")
  assert(asked[1].items[1].id == repo, "the focused project first: " .. asked[1].items[1].id)
  assert(selected().cwd == plain, "another project was chosen")
  -- On another host, the host reads the folder.
  again()
  relays, local_execs = 0, 0
  local theirs = open_session("studio", "there", repo .. "/src")
  theirs.attached = true
  answers = { nil }
  I.clean_up({ server = "studio", session_id = theirs.session_id, block_id = theirs.block_id })
  assert(asked[1].items[1].id == repo and local_execs == 0)
  close(nil, mine.session_id)
  close("studio", theirs.session_id)
  I.backend.forget{ project = inner }
end)

test("git's progress lines are not the reason", function()
  assert(I.reason("Preparing worktree (checking out 'main')\nfatal: 'main' is already used") == "fatal: 'main' is already used")
  assert(I.reason("error: one\nfatal: two") == "error: one\nfatal: two")
  assert(I.reason("no marker here") == "no marker here")
end)

test("a state file from the version before keeps its projects", function()
  write(tmp .. "/state/projects.json", '{"projects":["/a/b"],"last":{"/a/b":"current"}}')
  I.reset()
  local s = I.load_state()
  assert(#s.projects == 1 and s.projects[1] == "/a/b" and next(s.sessions) == nil)
  assert(#s.recent == 0, "no order of use yet")
end)

test("a corrupt state file is an empty list", function()
  write(tmp .. "/state/projects.json", "{not json")
  I.reset()
  assert(#I.load_state().projects == 0)
end)

tidy()
print(n .. " passed")
