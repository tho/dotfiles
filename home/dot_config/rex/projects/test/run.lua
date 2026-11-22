-- Tests for projects.lua against a stand-in for the rex table, real git and
-- real worktrunk (wt). Run from the repository's top folder:
--
--     lua5.1 test/run.lua
--
-- Any Lua 5.1 works, LuaJIT included. On a Mac, where Homebrew has disabled
-- lua@5.1: brew install luajit, then luajit test/run.lua. It needs git and wt
-- on PATH. wt runs with a config folder of its own, and finds a stand-in for
-- gh first on its PATH.

if _VERSION ~= "Lua 5.1" then
  io.stderr:write("test/run.lua needs Lua 5.1, not " .. tostring(_VERSION) ..
    ". On a Mac: brew install luajit, then luajit test/run.lua\n")
  os.exit(1)
end

local function sh(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- capture runs a shell command and returns what it printed, its exit status
-- and what it wrote to stderr.
local errfile = os.tmpname()
-- Like the Rex server, run commands with no terminal: wt opens /dev/tty
-- directly and would wait for an approval answer. macOS has no setsid.
local detach = "perl -MPOSIX -e 'POSIX::setsid(); exec \"/bin/sh\", \"-c\", $ARGV[0] or die \"exec: $!\"' "
local function capture(cmd)
  local p = io.popen(detach .. sh("{ " .. cmd .. "; } </dev/null 2>" .. sh(errfile) .. "; echo \"::$?\""))
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
    -- wt writes null for a value it has not got; it reads as nil.
    if s:sub(pos, pos + 3) == "null" then pos = pos + 4; return json.null end
    for word, v in pairs({ ["true"] = true, ["false"] = false }) do
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
-- makes that server not know the action; a string is the error it answers.
-- in_relay is set while an op runs there, and local_execs counts the
-- commands run outside of one: on the app's own server.
local relays, remote_missing, in_relay, local_execs = 0, false, false, 0

-- The sessions of each stand-in server, by the server's label, "local" for
-- the app's own. cwd is the folder of the session's terminal. attached says
-- whether calls on the session are let through: the real server refuses a
-- call on a session the caller is not attached to, and the app is attached
-- to the session an action is run from.
local stores, made = {}, 0
-- create_fails, when set, is the error session.create answers.
local create_fails = nil
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
      if create_fails ~= nil then return nil, create_fails end
      for _, w in ipairs(args.initial_windows) do
        if type(w) ~= "table" or type(w.layout) ~= "table" then return nil, "invalid_params: initial_windows" end
      end
      local first = args.initial_windows[1].layout.options
      local s = open_session(host, args.label, first and first.cwd)
      s.windows = args.initial_windows
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

-- prs are the pull requests of up, as gh pr list gives them, for the gh
-- that wt runs: see serve_prs.
local prs = {}

-- timeouts holds the time limit of each command run with one, as
-- { argv = ..., seconds = ..., relayed = boolean }. stalls, when set, says
-- which commands take longer than their limit: they are stopped, as the
-- real rex.exec stops them. envs holds the environment each command was
-- given, as { argv = ..., env = ..., relayed = boolean }.
local timeouts, stalls, envs = {}, nil, {}

-- base_env is what every command runs with: the stand-in gh first on PATH
-- and a config folder of its own for wt. serve_prs writes the files that
-- stand-in reads. Both are set once the temporary folder exists.
local base_env, serve_prs = {}, function() end

-- wt_argv logs the argv of every wt command. intercept, when set, is called
-- as intercept(argv, opts, real) for each command, and what it returns, when
-- not nil, is the answer instead: real runs the command as the stand-in does
-- without intercept.
local wt_argv, intercept = {}, nil

local run_exec
local function exec(argv, opts)
  if argv[1] == "wt" then wt_argv[#wt_argv + 1] = argv end
  if intercept ~= nil then
    local answer = intercept(argv, opts, run_exec)
    if answer ~= nil then return answer end
  end
  return run_exec(argv, opts)
end

rex = {
  json = json,
  log = function(level, msg) io.stderr:write("[" .. level .. "] " .. msg .. "\n") end,
  exec = exec,
}

run_exec = function(argv, opts)
  if not in_relay then local_execs = local_execs + 1 end
  if opts and opts.timeout then
    timeouts[#timeouts + 1] = { argv = argv, seconds = opts.timeout, relayed = in_relay }
    if stalls and stalls(argv) then
      return { ok = false, code = -1, signal = "SIGTERM", timed_out = true, stdout = "", stderr = "" }
    end
  end
  if opts and opts.env then envs[#envs + 1] = { argv = argv, env = opts.env, relayed = in_relay } end
  assert(argv[1] ~= "gh", "projects.lua ran gh: " .. table.concat(argv, " "))
  if argv[1] == "wt" then serve_prs() end
  -- env sets each variable, then runs the command; false removes one.
  local parts = { "env" }
  for _, set in ipairs({ base_env, opts and opts.env or {} }) do
    for k, v in pairs(set) do
      if v == false then
        parts[#parts + 1] = "-u " .. sh(k)
      else
        parts[#parts + 1] = sh(k .. "=" .. tostring(v))
      end
    end
  end
  for _, a in ipairs(argv) do parts[#parts + 1] = sh(a) end
  local cmd = table.concat(parts, " ")
  if opts and opts.cwd then cmd = "cd " .. sh(opts.cwd) .. " && " .. cmd end
  local out, code, err = capture(cmd)
  return { ok = code == 0, code = code, stdout = out, stderr = err }
end

for k, v in pairs({
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
    -- { text = ... } is typed text, { why = ... } a palette that failed for
    -- that reason (false: for none), a number is a row's place in the list,
    -- and a string is a row's title or id. No answer left is a cancel. A
    -- function is called with the list and returns the answer, for a test
    -- that looks around while a list shows.
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
      if type(a) == "table" and a.why ~= nil then return nil, a.why or nil end
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
      if remote_missing then return nil, remote_missing == true and "not_found: no action " .. args.action or remote_missing end
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
}) do rex[k] = v end

---------------------------------------------------------------------------
-- The repositories
---------------------------------------------------------------------------

-- Stop at once without wt: every worktree test would fail on it.
local wt_version, wt_code = capture("wt --version")
if wt_code ~= 0 then
  io.stderr:write("test/run.lua needs worktrunk (wt) on PATH: https://worktrunk.dev\n")
  os.exit(1)
end
print("with " .. (wt_version:gsub("%s+$", "")) .. " and " .. (capture("git --version"):gsub("%s+$", "")))

local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. sh(tmp))
-- Git spells a folder with every symbolic link followed, and /tmp is one on
-- macOS. Spell the folder that way from the start, so that paths compare.
tmp = capture("cd " .. sh(tmp) .. " && pwd -P"):gsub("%s+$", "")

-- The gh that wt runs. It answers the calls wt makes for wt switch pr:<n>:
-- the pull request from gh/pulls-<n>.json, or GitHub's 404; https as the
-- git protocol. It logs each call in gh/log.
local gh_dir = tmp .. "/gh"
os.execute("mkdir -p " .. sh(tmp .. "/bin") .. " " .. sh(gh_dir) .. " " .. sh(tmp .. "/xdg"))
local function write_file(path, text)
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end
write_file(tmp .. "/bin/gh", [[#!/bin/sh
dir=]] .. sh(gh_dir) .. [[

printf '%s\n' "$*" >> "$dir/log"
case "$1 $2 $3" in
  "config get git_protocol") echo https; exit 0 ;;
esac
case "$1 $2" in
  "api repos/"*)
    f="$dir/pulls-${2##*/}.json"
    [ -f "$f" ] && exec cat "$f"
    echo '{"message":"Not Found","status":"404"}'
    echo 'gh: Not Found (HTTP 404)' >&2
    exit 1 ;;
esac
echo "gh stand-in: no command $*" >&2
exit 1
]])
os.execute("chmod +x " .. sh(tmp .. "/bin/gh"))
base_env = { PATH = tmp .. "/bin:" .. os.getenv("PATH"), XDG_CONFIG_HOME = tmp .. "/xdg" }

-- owner_name reads the owner and repository of a pull request's address.
local function owner_name(url)
  return url:match("^https://github%.com/([^/]+)/([^/]+)/pull/%d+$")
end

-- serve_prs writes each pull request of prs as GitHub's API gives it, for
-- the gh that wt runs. A pull request with isCrossRepository comes from
-- contrib/fork.
serve_prs = function()
  os.execute("rm -f " .. sh(gh_dir) .. "/pulls-*.json")
  for _, p in ipairs(prs) do
    local owner, name = owner_name(p.url)
    local base = { name = name, owner = { login = owner } }
    local head = p.isCrossRepository and { name = "fork", owner = { login = "contrib" } } or base
    write_file(gh_dir .. "/pulls-" .. p.number .. ".json", json.encode({
      number = p.number, title = p.title, state = "open", draft = p.isDraft,
      user = { login = p.author.login }, html_url = p.url,
      head = { ref = p.headRefName, sha = p.headRefOid, repo = head },
      base = { ref = "main", repo = base },
    }))
  end
end

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
local function read(path)
  local f = io.open(path)
  if f == nil then return nil end
  local text = f:read("*a"); f:close()
  return text
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
-- feature-x. The remotes have the addresses of GitHub repositories,
-- https://github.com/remotes/up.git and …/remotes/fork.git, which wt reads
-- to find a pull request's remote, and git's url.<folder>.insteadOf takes
-- each to its folder.
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
local up_url, fork_url = "https://github.com/remotes/up.git", "https://github.com/remotes/fork.git"
git(repo, "config", "url." .. up .. ".insteadOf", up_url)
git(repo, "config", "url." .. fork .. ".insteadOf", fork_url)
git(repo, "remote", "set-url", "origin", up_url)
git(repo, "remote", "add", "upstream", fork_url)
git(repo, "fetch", "-q", "upstream")
git(repo, "branch", "feature-x")
local wt = tmp .. "/wt/my-app"

-- projects.lua reads SHELL from test_shell, so that the real login shell's
-- PATH does not hide the stand-in gh. nil keeps the server's environment.
local test_shell = nil
local real_getenv = os.getenv
os.getenv = function(name)
  if name == "SHELL" then return test_shell end
  return real_getenv(name)
end

package.loaded.projects = nil
local P = dofile("projects.lua").setup{
  worktrees = tmp .. "/wt",
  state_file = tmp .. "/state/projects.json",
  roots = {},
}
local I = P._internal

local function prime_login()
  local real_log = rex.log
  rex.log = function() end
  I.reset_login()
  I.tool_opts(nil)
  rex.log = real_log
end
prime_login()

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
local function branches(flow)
  local op = flow == "here" and I.backend.here_rows or I.backend.worktree_rows
  local list, at = ids(op{ project = repo }.rows)
  return list, at
end
local function cleanup_branches()
  local list, at = ids(I.backend.cleanup_rows{ project = repo }.rows)
  return list, at
end

-- ends runs f(ctx) with the answers given and returns its error, or nil,
-- and the lines it logged.
local function ends(list, f, ctx)
  answers = { unpack(list) }
  local logged, real_log = {}, rex.log
  rex.log = function(level, msg) logged[#logged + 1] = level .. " " .. msg end
  local ok, err = pcall(f, ctx)
  rex.log = real_log
  return (not ok) and tostring(err) or nil, logged
end
local function record(dir) return I.load_state().sessions[dir] end
local function remembered(dir) return record(dir) and record(dir).session end

-- close_kept closes the session remembered for dir, when it is on the app's
-- own server.
local function close_kept(dir)
  local id = remembered(dir)
  if id ~= nil and session(nil, id) ~= nil then close(nil, id) end
end

-- with_hooks gives wt the user config toml while f runs, then removes it:
-- every wt call reads it. logging_hooks is one whose pre-switch, pre-start
-- and pre-remove hooks write "switch <branch>", "start <branch>" and
-- "remove <branch>" to hook_log, outside any worktree, and ran says whether
-- such a line is there.
local user_config, hook_log = tmp .. "/xdg/worktrunk/config.toml", tmp .. "/hook-log"
local logging_hooks = '[pre-switch]\nlog = "echo switch {{ branch }} >> ' .. hook_log .. '"\n' ..
  '[pre-start]\nlog = "echo start {{ branch }} >> ' .. hook_log .. '"\n' ..
  '[pre-remove]\nlog = "echo remove {{ branch }} >> ' .. hook_log .. '"\n'
local function with_hooks(toml, f)
  os.execute("mkdir -p " .. sh(tmp .. "/xdg/worktrunk"))
  write(user_config, toml)
  os.remove(hook_log)
  local ok, err = pcall(f)
  os.remove(user_config)
  if not ok then error(err, 0) end
end
local function ran(line)
  return ("\n" .. (read(hook_log) or "")):find("\n" .. line .. "\n", 1, true) ~= nil
end

-- wt_runs returns the argv of each wt command of verb, such as switch, run
-- since wt_argv held from of them. holds says whether argv has word.
local function wt_runs(from, verb)
  local list = {}
  for i = from + 1, #wt_argv do
    if wt_argv[i][4] == verb then list[#list + 1] = wt_argv[i] end
  end
  return list
end
local function holds(argv, word)
  for _, w in ipairs(argv) do if w == word then return true end end
  return false
end

-- stopped is what rex.exec answers for a command stopped at its time limit.
local function stopped()
  return { ok = false, code = -1, signal = "SIGTERM", timed_out = true, stdout = "", stderr = "" }
end

---------------------------------------------------------------------------
-- The palette and the keys
---------------------------------------------------------------------------

test("the Projects section holds the five entries, and the backend sits elsewhere", function()
  local titles = {}
  for _, spec in pairs(actions) do
    if spec.category == "Projects" then titles[#titles + 1] = spec.title end
  end
  table.sort(titles)
  local want = { "Add Project to List…", "Clean Up Branch in Project…", "Open Worktree in Project…",
    "Remove Project from List…", "Switch Branch in Project…" }
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
  assert(I.expand("  ~/x  ") == os.getenv("HOME") .. "/x")
  assert(I.expand('"/a/b"') == "/a/b")
  assert(I.expand("/a\\b") == "/a\\b", "a backslash is part of a Unix name")
  assert(I.basename("/a/b/") == "b")
end)

test("add a project, then it is listed and kept with its session", function()
  answers = { "Add project…", { text = repo }, 1 }
  I.switch_run({})
  local s = selected()
  assert(s.cwd == repo and s.label == "my-app", "the main session is named after the project")
  local text = read(tmp .. "/state/projects.json")
  assert(text:find("my-app", 1, true), "state file written: " .. text)
  -- Read the file again: the list and the session id come from it.
  I.reset()
  local rows = I.project_rows()
  assert(rows[1].title == "my-app" and rows[#rows].title == "Add project…")
  assert(remembered(repo) == s.session_id, "the session id is in projects.json")
end)

test("plain folder: both modes go to its one session", function()
  answers = { "Add project…", { text = plain }, "Add plain" }
  I.switch_run({})
  assert(#asked == 3, "a plain folder has no branch list")
  local s = selected()
  assert(s.cwd == plain and s.label == "plain")
  assert(created() == 1)
  again()
  answers = { "plain" }
  I.worktree_run({})
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
  I.switch_run({})
  local page = asked[3]
  assert(page.items[1].title == "Add code", "the nearest folder: " .. page.items[1].title)
  assert(page.value == "my-", "what was not found is the filter: " .. tostring(page.value))
  assert(created() == 0 and #queued == 0)
  -- A name typed in the browser is inside the folder it shows.
  again()
  answers = { "Add project…", { text = tmp }, { text = "code/my-app" }, 1 }
  I.switch_run({})
  assert(asked[4].title == "Switch branch in my-app", asked[4].title)
  assert(asked[3].value == nil, "a folder that exists has no filter")
end)

test("a path typed in the project picker opens the browser there", function()
  answers = { { text = tmp .. "/code/my" } }
  I.switch_run({})
  assert(asked[1].allow_other, "the project picker takes a path")
  assert(asked[2].title == "Add project" and asked[2].value == "my")
  assert(asked[2].items[1].title == "Add code")
  -- A repository is added at once, and the flow moves on to its branches.
  again()
  answers = { { text = repo }, 1 }
  I.switch_run({})
  assert(asked[2].title == "Switch branch in my-app", asked[2].title)
  assert(selected().cwd == repo)
end)

test("blank typed text ends Add Project quietly", function()
  local saved = I.backend.saved().rows
  for _, list in ipairs({
    { { text = "" } },
    { { text = "  " } },
    { { text = '""' } },
    { "Add project…", { text = "" } },
    { "Add project…", { text = tmp .. "/code" }, { text = " " } },
  }) do
    again()
    local err, logged = ends(list, I.switch_run, {})
    assert(err == nil and #logged == 0, tostring(err))
    assert(#asked == #list, "nothing more was asked: " .. #asked)
  end
  assert(created() == 0 and #queued == 0)
  assert(#I.backend.saved().rows == #saved, "nothing was added")
  local typed = I.backend.typed{ text = "" }
  assert(typed.why ~= nil and typed.why ~= "cancelled", tostring(typed.why))
end)

test("the browser lists folders alike, and Return on one adds it", function()
  answers = { "Add project…", { text = tmp .. "/code" } }
  I.switch_run({})
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
  I.switch_run({})
  assert(asked[4].title == "Switch branch in my-app")
  assert(selected().cwd == repo)
end)

test("Return on a plain folder opens it and .. goes back up", function()
  answers = { "Add project…", { text = tmp }, "code", ".." }
  I.switch_run({})
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
  I.switch_run({})
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
  I.switch_run({})
  local first = asked[2].items[1]
  assert(first.id == "HEAD" and first.subtitle == "detached", first.id)
  assert(#asked == 2 and selected().session_id == main and created() == 0)
  assert(select(2, try(repo, "symbolic-ref", "-q", "HEAD")) ~= 0, "still detached")
  git(repo, "switch", "-q", "main")
end)

test("here: a local branch is switched to, in the same session", function()
  local main = remembered(repo)
  answers = { "my-app", "feature-x" }
  I.switch_run({})
  assert(#asked == 2, "no base for a branch that exists")
  assert(branch_of(repo) == "feature-x")
  assert(selected().session_id == main and created() == 0)
end)

test("here: a remote branch becomes a local one that tracks the remote picked", function()
  answers = { "my-app", "upstream/shared" }
  I.switch_run({})
  assert(#asked == 2)
  assert(branch_of(repo) == "shared", "the local branch has the plain name")
  assert(git(repo, "rev-parse", "--abbrev-ref", "shared@{upstream}") == "upstream/shared")
  local list, at = branches("here")
  assert(list[1] == "shared" and not at["origin/shared"] and not at["upstream/shared"])
end)

test("here: a new name asks for a base, and a remote base is not tracked", function()
  answers = { "my-app", { text = " feat login " }, "origin/pr-1" }
  I.switch_run({})
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
  I.switch_run({})
  assert(branch_of(repo) == "from-default")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/main"))
  -- A remote branch is one however it is written.
  answers = { "my-app", { text = "from-long" }, { text = "remotes/origin/pr-1" } }
  I.switch_run({})
  assert(branch_of(repo) == "from-long")
  assert(git(repo, "rev-parse", "HEAD") == git(repo, "rev-parse", "origin/pr-1"))
  assert(select(2, try(repo, "config", "--get", "branch.from-long.remote")) ~= 0, "--no-track")
  answers = { "my-app", { text = "from-typed" }, { text = "origin/pr-1" } }
  I.switch_run({})
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
  local function rows(flow)
    local op = flow == "here" and I.backend.here_rows or I.backend.worktree_rows
    return ids(op{ project = dir }.rows)
  end

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
  local r = I.backend.name{ project = repo, name = "x1" }
  assert(r.name == "x1" and r.rows[1].id == "feature-x" and r.rows[2].id == "from-typed")
  P.setup{ base = "develop" }
  r = I.backend.name{ project = repo, name = "x1" }
  assert(r.rows[1].id == "from-typed", "first is the current branch: " .. r.rows[1].id)
  P.setup{ base = false }
  assert(not has_branch(repo, "x1"), "asking for the base rows makes nothing")

  -- A base with no local branch is found on a remote by its name, and
  -- origin's wins over another remote's.
  -- The other remote's has the newer commit, so it is listed before origin's.
  git(up, "branch", "byname")
  git(fork, "switch", "-q", "-c", "byname")
  commit(fork, "byname", "newer\n", "newer on the other remote")
  git(fork, "switch", "-q", "-")
  git(repo, "fetch", "-q", "origin")
  git(repo, "fetch", "-q", "upstream")
  assert(not has_branch(repo, "byname"))
  P.setup{ base = "byname" }
  r = I.backend.name{ project = repo, name = "x1" }
  assert(r.rows[1].id == "origin/byname" and r.rows[1].subtitle == "default · fetched first",
    r.rows[1].id .. " · " .. tostring(r.rows[1].subtitle))
  -- So is a local branch that follows nothing.
  git(repo, "branch", "-q", "--no-track", "byname", "origin/byname")
  r = I.backend.name{ project = repo, name = "x1" }
  assert(r.rows[1].id == "origin/byname", r.rows[1].id)
  git(repo, "branch", "-q", "-D", "byname")
  -- A base written as a remote branch is that remote branch.
  P.setup{ base = "upstream/byname" }
  r = I.backend.name{ project = repo, name = "x1" }
  assert(r.rows[1].id == "upstream/byname" and r.rows[1].subtitle == "default · fetched first",
    r.rows[1].id .. " · " .. tostring(r.rows[1].subtitle))
  P.setup{ base = false }
  git(up, "branch", "-q", "-D", "byname")
  git(fork, "branch", "-q", "-D", "byname")
  git(repo, "fetch", "-q", "--prune", "origin")
  git(repo, "fetch", "-q", "--prune", "upstream")
end)

test("the default base is fetched first, in both modes, and no other base is", function()
  -- origin's main moves on, and local main has a commit that is not pushed.
  git(repo, "switch", "-q", "main")
  commit(up, "g", "new upstream\n", "upstream moves")
  commit(repo, "h", "local only\n", "not pushed")
  local upstream_main, local_main = git(up, "rev-parse", "main"), git(repo, "rev-parse", "main")
  assert(git(repo, "rev-parse", "origin/main") ~= upstream_main, "not fetched yet")

  answers = { "my-app", { text = "fresh-here" }, 1 }
  I.switch_run({})
  assert(branch_of(repo) == "fresh-here")
  assert(git(repo, "rev-parse", "HEAD") == upstream_main, "starts from origin/main as it is now")
  assert(select(2, try(repo, "config", "--get", "branch.fresh-here.remote")) ~= 0, "--no-track")
  assert(git(repo, "rev-parse", "main") == local_main, "local main is left alone")

  commit(up, "g", "newer upstream\n", "upstream moves again")
  upstream_main = git(up, "rev-parse", "main")
  answers = { "my-app", { text = "fresh-wt" }, "origin/main" }
  I.worktree_run({})
  assert(git(wt .. "/fresh-wt", "rev-parse", "HEAD") == upstream_main, "a worktree fetches too")

  -- Local main, chosen on purpose, is taken as it is, and nothing is fetched.
  commit(up, "g", "newest upstream\n", "upstream moves once more")
  local before = git(repo, "rev-parse", "origin/main")
  git(repo, "switch", "-q", "fresh-here")
  answers = { "my-app", { text = "from-local" }, "main" }
  I.worktree_run({})
  assert(git(wt .. "/from-local", "rev-parse", "HEAD") == local_main, "local main, unpushed commit and all")
  assert(git(repo, "rev-parse", "origin/main") == before, "nothing was fetched")

  -- A fetch that fails stops the action with git's message.
  git(repo, "remote", "set-url", "origin", tmp .. "/nowhere")
  answers = { "my-app", { text = "offline" }, 1 }
  local message = refused(I.switch_run, {})
  git(repo, "remote", "set-url", "origin", up_url)
  assert(message:find("^fatal:"), message)
  assert(not has_branch(repo, "offline") and branch_of(repo) == "fresh-here", "nothing changed")

  -- A default with no remote branch is listed as it is.
  P.setup{ base = "feature-x" }
  local r = I.backend.name{ project = repo, name = "x2" }
  assert(r.rows[1].id == "feature-x" and r.rows[1].subtitle == "default")
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
  local r = I.backend.name{ project = clone, name = "t1" }
  assert(r.rows[1].id == "origin/trunk" and r.rows[1].subtitle == "default · fetched first",
    "origin's HEAD names the default: " .. r.rows[1].id)
  -- The setting wins over what the remote says.
  git(clone, "branch", "other")
  P.setup{ base = "other" }
  r = I.backend.name{ project = clone, name = "t1" }
  assert(r.rows[1].id == "other" and r.rows[1].subtitle == "default", r.rows[1].id)
  P.setup{ base = false }
  -- wt keeps what it found in git config, and that is what counts after.
  assert(git(clone, "config", "--get", "worktrunk.default-branch") == "trunk", "wt recorded it")
  git(clone, "config", "worktrunk.default-branch", "other")
  r = I.backend.name{ project = clone, name = "t1" }
  assert(r.rows[1].id == "other" and r.rows[1].subtitle == "default", "wt's record: " .. r.rows[1].id)
  -- With no default at all the first row is the current branch.
  git(clone, "config", "worktrunk.default-branch", "nowhere")
  r = I.backend.name{ project = clone, name = "t1" }
  assert(r.rows[1].id == "trunk" and r.rows[1].subtitle == "current branch", r.rows[1].id)
  assert(not has_branch(clone, "t1"), "asking for the base rows makes nothing")
end)

test("on another host the remote is not asked for the default branch", function()
  -- A remote added by hand has no HEAD, so wt would ask it, and give up
  -- only after 10 seconds. This one never answers.
  local dir = tmp .. "/code/no-head"
  os.execute("mkdir -p " .. sh(dir))
  git(dir, "init", "-q", "-b", "trunk")
  commit(dir, "f", "0\n", "init")
  git(dir, "remote", "add", "origin", "ssh://nowhere.invalid/x.git")
  git(dir, "config", "core.sshCommand", "sleep 30; false")
  envs = {}
  local started = os.time()
  local r = actions.projects_backend.run({}, { op = "name", relayed = true,
    args = { project = dir, name = "t1" } })
  assert(os.time() - started <= 3, "answered in " .. (os.time() - started) .. " seconds")
  assert(r.rows[1].id == "trunk" and r.rows[1].subtitle == "default", r.rows[1].id)
  assert(git(dir, "config", "--get", "worktrunk.default-branch") == "trunk", "wt recorded what it found")
  for _, e in ipairs(envs) do
    if e.argv[1] == "wt" then assert(e.env.GIT_ALLOW_PROTOCOL == "none", "wt kept off the network") end
  end
  -- So the next wt command reads the record, and a new worktree is quick.
  started = os.time()
  r = actions.projects_backend.run({}, { op = "open_worktree", relayed = true,
    args = { project = dir, name = "t1", base = "trunk" } })
  assert(r.dir == tmp .. "/wt/no-head/t1", tostring(r.why))
  assert(os.time() - started <= 3, "answered in " .. (os.time() - started) .. " seconds")
end)

test("name says what a branch is, and makes nothing", function()
  local function name(n) return I.backend.name{ project = repo, name = n } end
  local r = name("feature-x")
  assert(r.name == "feature-x" and r.rows == nil and r.why == nil, "an existing branch")
  local current = branch_of(repo)
  r = name(current)
  assert(r.name == current and r.rows == nil, "the current branch")
  r = name("origin/pr-1")
  assert(r.name == "origin/pr-1" and r.rows == nil, "a remote branch")
  r = name(" feat signup ")
  assert(r.name == "feat-signup" and r.rows ~= nil and r.why == nil, "a new branch, spaces as dashes")
  local list = ids(r.rows)
  local want = ids(I.backend.name{ project = repo, name = "other-new" }.rows)
  assert(table.concat(list, " ") == table.concat(want, " "), "the base rows")
  assert(not has_branch(repo, "feat-signup"), "nothing made")
  r = name("bad..name")
  assert(r.why == "fatal: 'bad..name' is not a valid branch name" and r.name == nil, tostring(r.why))
  assert(name("").why == "no branch was named" and name("  ").why == "no branch was named")
  r = I.backend.name{ project = plain, name = "x" }
  assert(r.why ~= nil and r.name == nil, "a plain folder")

  git(repo, "switch", "-q", "--detach")
  r = name("HEAD")
  git(repo, "switch", "-q", current)
  assert(r.name == "HEAD" and r.rows == nil, "a detached main checkout")

  -- wt's shortcuts and pull requests are names the open ops read.
  for _, typed in ipairs({ "^", "-", "pr:9", "https://github.com/remotes/up/pull/8" }) do
    r = name(typed)
    assert(r.name == typed and r.rows == nil and r.why == nil, typed)
  end
  -- A bare number is a branch name, and so is a link with no pull request.
  for _, typed in ipairs({ "123", "#12" }) do
    r = name(typed)
    assert(r.name == typed and r.rows ~= nil, typed)
  end
  assert(name("https://github.com/o/r/pulls").why ~= nil, "a link to no pull request")
  git(repo, "switch", "-q", "-c", "prev-one")
  git(repo, "switch", "-q", current)
  r = name("@{-1}")
  assert(r.why == "@{-1} is not a branch name: git reads it as prev-one" and r.name == nil, tostring(r.why))
  git(repo, "branch", "-q", "-D", "prev-one")
end)

test("open without a base for a new name answers why and makes nothing", function()
  for flow, open in pairs({ here = I.backend.switch_here, worktree = I.backend.open_worktree }) do
    local before = branch_of(repo)
    local r = open{ project = repo, name = "no-base" }
    assert(r.why == "no base was named" and r.dir == nil, flow .. ": " .. tostring(r.why))
    assert(not has_branch(repo, "no-base") and branch_of(repo) == before, flow .. ": nothing made")
  end
end)

test("each flow opens a branch with one open call, a new one too", function()
  local opens, real_here, real_worktree = {}, I.backend.switch_here, I.backend.open_worktree
  I.backend.switch_here = function(a) opens[#opens + 1] = a; return real_here(a) end
  I.backend.open_worktree = function(a) opens[#opens + 1] = a; return real_worktree(a) end
  local start = branch_of(repo)
  local ok, err = pcall(function()
    answers = { "my-app", { text = "one-call-here" }, "main" }
    I.switch_run({})
    assert(#opens == 1 and opens[1].name == "one-call-here" and opens[1].base == "main",
      "here, new: " .. #opens)
    assert(branch_of(repo) == "one-call-here")
    git(repo, "switch", "-q", start)
    git(repo, "branch", "-q", "-D", "one-call-here")

    opens = {}
    answers = { "my-app", { text = "one-call-wt" }, "main" }
    I.worktree_run({})
    assert(#opens == 1 and opens[1].name == "one-call-wt" and opens[1].base == "main",
      "worktree, new: " .. #opens)
    assert(has_branch(repo, "one-call-wt"))
    git(repo, "worktree", "remove", wt .. "/one-call-wt")
    git(repo, "branch", "-q", "-D", "one-call-wt")

    opens = {}
    local pickers = #asked
    answers = { "my-app", { text = "feature-x" } }
    I.switch_run({})
    assert(#opens == 1 and opens[1].name == "feature-x" and opens[1].base == nil,
      "here, existing: " .. #opens)
    assert(#asked == pickers + 2, "no base list")
    git(repo, "switch", "-q", start)

    opens = {}
    pickers = #asked
    git(repo, "branch", "-q", "one-call-old", "main")
    answers = { "my-app", { text = "one-call-old" } }
    I.worktree_run({})
    assert(#opens == 1 and opens[1].name == "one-call-old" and opens[1].base == nil,
      "worktree, existing: " .. #opens)
    assert(#asked == pickers + 2, "no base list in worktree mode")
    git(repo, "worktree", "remove", wt .. "/one-call-old")
    git(repo, "branch", "-q", "-D", "one-call-old")
  end)
  I.backend.switch_here, I.backend.open_worktree = real_here, real_worktree
  if not ok then error(err, 0) end
end)

test("here: a name git does not take is refused with git's words, before any base", function()
  answers = { "my-app", { text = "bad..name" } }
  local message = refused(I.switch_run, {})
  assert(#asked == 2)
  assert(message == "fatal: 'bad..name' is not a valid branch name", message)
  assert(#queued == 0)
end)

test("@{-1} and @ are refused in both flows, before any base", function()
  local start = branch_of(repo)
  git(repo, "switch", "-q", "-c", "prev-two")
  git(repo, "switch", "-q", start)
  for flow, run in pairs({ here = I.switch_run, worktree = I.worktree_run }) do
    again()
    answers = { "my-app", { text = "@{-1}" } }
    local message = refused(run, {})
    assert(message == "@{-1} is not a branch name: git reads it as prev-two", flow .. ": " .. message)
    assert(#asked == 2 and #queued == 0 and created() == 0, flow .. ": no base, no session")
    local r = (flow == "here" and I.backend.switch_here or I.backend.open_worktree){
      project = repo, name = "@{-1}", base = "main" }
    assert(r.why == message and r.dir == nil, flow .. ": the open op says the same")
  end
  for flow, run in pairs({ here = I.switch_run, worktree = I.worktree_run }) do
    again()
    answers = { "my-app", { text = "@" } }
    local message = refused(run, {})
    assert(message == "@ is not a branch name: git reads it as HEAD", flow .. ": " .. message)
    assert(#asked == 2 and #queued == 0 and created() == 0, flow .. ": @, no base, no session")
  end
  local r = I.backend.name{ project = repo, name = "@" }
  assert(r.why == "@ is not a branch name: git reads it as HEAD" and r.name == nil, tostring(r.why))
  assert(branch_of(repo) == start and not exists(wt .. "/prev-two"), "nothing switched or made")
  git(repo, "branch", "-q", "-D", "prev-two")
end)

test("a bare number is a new branch in both flows", function()
  for flow, run in pairs({ here = I.switch_run, worktree = I.worktree_run }) do
    again()
    local err = ends({ "my-app", { text = "123" } }, run)
    assert(err == nil, flow .. ": " .. tostring(err))
    assert(#asked == 3 and asked[3].title == "Start 123 from", flow .. ": the base list is asked")
    assert(not has_branch(repo, "123") and #queued == 0, flow .. ": cancelled, nothing made")
  end
end)

test("a blank name or a blank base ends either flow quietly", function()
  local start = branch_of(repo)
  for flow, run in pairs({ here = I.switch_run, worktree = I.worktree_run }) do
    for _, list in ipairs({
      { "my-app", { text = "" } },
      { "my-app", { text = "   " } },
      { "my-app", { text = "blank-base" }, { text = " " } },
    }) do
      again()
      local err = ends(list, run)
      assert(err == nil, flow .. ": " .. tostring(err))
      assert(#queued == 0 and created() == 0, flow .. ": no session")
    end
  end
  assert(not has_branch(repo, "blank-base") and not exists(wt .. "/blank-base"), "nothing made")
  assert(branch_of(repo) == start, "nothing switched")
end)

test("here: when git refuses to switch, its message is the error and nothing changes", function()
  git(repo, "switch", "-q", "main")
  -- f differs between main and feat-login, so git will not carry the change.
  write(repo .. "/f", "mine\n")
  answers = { "my-app", "feat-login" }
  local message = refused(I.switch_run, {})
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
  I.worktree_run({})
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
  local rows = I.backend.worktree_rows{ project = repo }.rows
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
  I.worktree_run({})
  assert(#asked == 2)
  assert(selected().session_id == id and created() == 0)
end)

test("worktree: a local branch and a remote branch each get a worktree and a session", function()
  answers = { "my-app", "feature-x" }
  I.worktree_run({})
  assert(#asked == 2, "no base for a branch that exists")
  local s = selected()
  assert(s.cwd == wt .. "/feature-x" and s.label == "my-app · feature-x")
  answers = { "my-app", "origin/pr-1" }
  I.worktree_run({})
  s = selected()
  assert(s.cwd == wt .. "/pr-1" and s.label == "my-app · pr-1", "the local branch has the plain name")
  assert(git(repo, "rev-parse", "--abbrev-ref", "pr-1@{upstream}") == "origin/pr-1")
  assert(created() == 2)
end)

test("worktree: a new branch from a remote base is not tracked", function()
  answers = { "my-app", { text = "topic" }, "origin/main" }
  I.worktree_run({})
  assert(branch_of(wt .. "/topic") == "topic")
  assert(select(2, try(repo, "config", "--get", "branch.topic.remote")) ~= 0, "--no-track")
end)

test("worktree: the main checkout's branch, typed, goes to the project's session", function()
  -- It is not on the list, but it can be typed.
  answers = { "my-app", { text = "main" } }
  I.worktree_run({})
  local s = selected()
  assert(s.cwd == repo and s.label == "my-app" and s.session_id == remembered(repo), s.label)
  assert(created() == 0 and not exists(wt .. "/main"))
end)

test("worktree: when wt refuses, its message is the error and no session is made", function()
  git(repo, "branch", "occupied")
  os.execute("mkdir -p " .. sh(wt .. "/occupied"))
  write(wt .. "/occupied/junk", "x")
  answers = { "my-app", "occupied" }
  local message = refused(I.worktree_run, {})
  local want = "Directory already exists: " .. wt .. "/occupied. To remove manually, run "
  assert(message:sub(1, #want) == want, message)
  assert(not message:find("\n") and not message:find("✗", 1, true), "one line, without wt's marks")
  assert(created() == 0 and #queued == 0)
  assert(exists(wt .. "/occupied/junk"), "the folder is left alone")
  os.execute("rm -rf " .. sh(wt .. "/occupied"))
  git(repo, "branch", "-q", "-D", "occupied")
end)

test("worktree: hooks run for your own branches, and a project's need wt's approval", function()
  git(repo, "branch", "hook-local")
  git(up, "branch", "hook-remote")
  git(repo, "fetch", "-q", "origin")
  local made = {}
  with_hooks(logging_hooks, function()
    for _, case in ipairs({
      { answers = { { text = "hook-new" }, 1 }, branch = "hook-new" },
      { answers = { { text = "hook-local" } }, branch = "hook-local" },
      { answers = { { text = "origin/hook-remote" } }, branch = "hook-remote" },
    }) do
      again()
      local from = #wt_argv
      answers = { "my-app", unpack(case.answers) }
      I.worktree_run({})
      local s = selected()
      assert(s.cwd == wt .. "/" .. case.branch, case.branch .. ": " .. s.cwd)
      made[#made + 1] = s
      local runs = wt_runs(from, "switch")
      assert(#runs == 1, case.branch .. ": one wt switch")
      assert(not holds(runs[1], "--no-hooks") and not holds(runs[1], "--yes"), table.concat(runs[1], " "))
      assert(ran("start " .. case.branch), case.branch .. ": the user's hook ran: " .. tostring(read(hook_log)))
    end
  end)

  -- A project hook needs approval, which wt cannot ask for without a terminal.
  os.execute("mkdir -p " .. sh(repo .. "/.config"))
  write(repo .. "/.config/wt.toml", '[pre-start]\nmark = "touch hook-ran"\n')
  again()
  answers = { "my-app", { text = "needs-ok" }, 1 }
  local message = refused(I.worktree_run, {})
  os.execute("rm -rf " .. sh(repo .. "/.config"))
  local asks = " needs approval to execute 1 command: pre-start mark: touch hook-ran. "
  local tail = "wt cannot ask for approval without a terminal: run wt config approvals add in a terminal in " ..
    I.short(repo) .. ", then try again"
  assert(message:find(asks, 1, true) and message:sub(-#tail) == tail, message)
  assert(not message:find("--yes", 1, true) and not message:find("\n"), message)
  assert(created() == 0 and #queued == 0 and not has_branch(repo, "needs-ok") and not exists(wt .. "/needs-ok"),
    "nothing made")

  for _, s in ipairs(made) do
    close(nil, s.session_id)
    I.backend.forget_record{ path = s.cwd }
    git(repo, "worktree", "remove", s.cwd)
  end
  for _, b in ipairs({ "hook-new", "hook-local", "hook-remote" }) do git(repo, "branch", "-q", "-D", b) end
  git(up, "branch", "-q", "-D", "hook-remote")
  git(repo, "update-ref", "-d", "refs/remotes/origin/hook-remote")
end)

test("worktree: a blocking hook that fails says wt's words, and opening again lands in the worktree", function()
  local message
  with_hooks('[pre-start]\nfail = "exit 3"\n', function()
    answers = { "my-app", { text = "hook-fails" }, 1 }
    message = refused(I.worktree_run, {})
  end)
  assert(message == "pre-start user:fail failed (exit code 3). To skip pre-start hooks, re-run with --no-hooks",
    message)
  assert(created() == 0 and exists(wt .. "/hook-fails"), "wt made the worktree, and no session")
  again()
  local from = #wt_argv
  answers = { "my-app", { text = "hook-fails" } }
  I.worktree_run({})
  local s = selected()
  assert(s.cwd == wt .. "/hook-fails" and created() == 1, s.cwd)
  assert(#wt_runs(from, "switch") == 0, "the worktree is there")
  close(nil, s.session_id)
  I.backend.forget_record{ path = s.cwd }
  git(repo, "worktree", "remove", s.cwd)
  git(repo, "branch", "-q", "-D", "hook-fails")
end)

test("worktree: a revision such as main~1 is no branch, and makes no worktree", function()
  local before = #I.worktrees(repo)
  answers = { "my-app", { text = "main~1" } }
  local title = refused(I.worktree_run, {})
  assert(#asked == 2, "project, then name: no base is asked for")
  assert(title:find("^fatal: ") and title:find("'main~1'", 1, true), "git's refusal: " .. title)
  assert(created() == 0 and #queued == 0, "no session")
  assert(#I.worktrees(repo) == before and not exists(wt .. "/main~1"), "no worktree")
end)

test("here: a typed branch that lives in a worktree shows git's refusal", function()
  answers = { "my-app", { text = "feat/x" } }
  local title = refused(I.switch_run, {})
  assert(title:find("^fatal: ") and title:find("'feat/x'", 1, true) and title:find("worktree", 1, true), title)
  assert(branch_of(repo) == "main" and #queued == 0, "nothing switched")
end)

test("worktree: ^ opens the default branch's checkout, the main one here", function()
  assert(branch_of(repo) == "main")
  answers = { "my-app", { text = "^" } }
  I.worktree_run({})
  assert(#asked == 2, "no base")
  local s = selected()
  assert(s.cwd == repo and s.label == "my-app" and s.session_id == remembered(repo), s.label)
  assert(created() == 0 and not exists(wt .. "/main"))
end)

test("worktree: - opens wt's previous branch, and without one says wt's words", function()
  git(repo, "config", "worktrunk.history", "feature-x")
  answers = { "my-app", { text = "-" } }
  I.worktree_run({})
  assert(#asked == 2, "no base")
  local s = selected()
  assert(s.cwd == wt .. "/feature-x" and s.label == "my-app · feature-x", s.cwd .. " · " .. s.label)
  git(repo, "config", "--unset", "worktrunk.history")
  again()
  answers = { "my-app", { text = "-" } }
  local message = refused(I.worktree_run, {})
  assert(message:find("No previous branch", 1, true), message)
  assert(#queued == 0 and created() == 0)
end)

test("worktree: ^ and - run hooks, as in a terminal", function()
  local dir = wt .. "/feature-x"
  close_kept(dir)
  I.backend.forget_record{ path = dir }
  try(repo, "worktree", "remove", dir)
  with_hooks(logging_hooks, function()
    for _, case in ipairs({ { typed = "^", hook = "switch main" }, { typed = "-", hook = "start feature-x" } }) do
      git(repo, "config", "worktrunk.history", "feature-x")
      again()
      local from = #wt_argv
      answers = { "my-app", { text = case.typed } }
      I.worktree_run({})
      local runs = wt_runs(from, "switch")
      assert(#runs == 1 and not holds(runs[1], "--no-hooks"), case.typed .. ": " .. table.concat(runs[1] or {}, " "))
      assert(ran(case.hook), case.typed .. ": the hook ran: " .. tostring(read(hook_log)))
    end
  end)
  git(repo, "config", "--unset", "worktrunk.history")
  assert(exists(dir), "wt made the worktree of -")
end)

test("here: wt's shortcuts and pull requests are refused with what takes them", function()
  local start = branch_of(repo)
  local want = {
    ["^"] = "^ is wt's shortcut for the default branch, which Switch Branch does not take: " ..
      "type the branch's name, or use Open Worktree",
    ["-"] = "- is wt's shortcut for the previous branch, which Switch Branch does not take: " ..
      "type the branch's name, or use Open Worktree",
    ["pr:9"] = "pr:9 is a pull request, which Switch Branch does not open: use Open Worktree",
    ["https://github.com/remotes/up/pull/8"] = "https://github.com/remotes/up/pull/8 is a pull request, " ..
      "which Switch Branch does not open: use Open Worktree",
  }
  for typed, why in pairs(want) do
    again()
    answers = { "my-app", { text = typed } }
    local message = refused(I.switch_run, {})
    assert(message == why, typed .. ": " .. message)
    assert(#asked == 2 and #queued == 0 and created() == 0, typed .. ": no base, no session")
    assert(branch_of(repo) == start, typed .. ": nothing switched")
  end
end)

---------------------------------------------------------------------------
-- Finding a checkout's session
---------------------------------------------------------------------------

test("lookup: a remembered session that is gone is replaced by a new one", function()
  local old = remembered(repo)
  close(nil, old)
  answers = { "my-app", 1 }
  I.switch_run({})
  local s = selected()
  assert(s.session_id ~= old and created() == 1)
  assert(remembered(repo) == s.session_id, "the stale id is replaced")
  assert(record(repo).created == true, "rex-projects made it")
end)

test("lookup: the session the action ran from is adopted when its terminal is inside", function()
  close(nil, remembered(repo))
  os.execute("mkdir -p " .. sh(repo .. "/src"))
  local mine = open_session(nil, "quiet-meadow", repo .. "/src")
  -- The shell was started somewhere else and has changed folder since.
  mine.attached, mine.started = true, plain
  answers = { "my-app", 1 }
  I.switch_run({ session_id = mine.session_id, block_id = mine.block_id })
  assert(created() == 0, "no new session")
  assert(mine.label == "my-app", "it is renamed: " .. mine.label)
  assert(selected() == mine and remembered(repo) == mine.session_id)
  assert(record(repo).created == false, "it is adopted, not made")
end)

test("lookup: a hand-made session in a worktree folder becomes that worktree's session", function()
  close(nil, remembered(wt .. "/feat-x"))
  local mine = open_session(nil, "calm-river", wt .. "/feat-x")
  mine.attached = true
  answers = { "my-app", "feat/x" }
  -- Without a block id, the session's focused block is asked.
  I.worktree_run({ session_id = mine.session_id })
  assert(created() == 0 and mine.label == "my-app · feat/x", mine.label)
  assert(selected() == mine and remembered(wt .. "/feat-x") == mine.session_id)
end)

test("lookup: a remembered session that lives wins over the one the action ran from", function()
  local main = remembered(repo)
  local other = open_session(nil, "other", repo)
  other.attached = true
  answers = { "my-app", 1 }
  I.switch_run({ session_id = other.session_id, block_id = other.block_id })
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
  I.switch_run({ session_id = theirs.session_id, block_id = theirs.block_id })
  assert(created() == 1 and selected() ~= theirs)
  assert(theirs.label == "my-app · feat/x" and remembered(wt .. "/feat-x") == theirs.session_id)
  theirs.cwd = wt .. "/feat-x"
end)

test("lookup: a terminal that is somewhere else gets a new session", function()
  close(nil, remembered(repo))
  local mine = open_session(nil, "elsewhere", plain)
  mine.attached = true
  answers = { "my-app", 1 }
  I.switch_run({ session_id = mine.session_id, block_id = mine.block_id })
  assert(created() == 1 and selected() ~= mine and mine.label == "elsewhere")
  close(nil, mine.session_id)
end)

-- in_terminal runs wt or git in dir, the way a person does in a terminal.
local function in_terminal(dir, ...)
  local words = {}
  for i, w in ipairs({ ... }) do words[i] = sh(w) end
  local _, code, err = capture("cd " .. sh(dir) .. " && XDG_CONFIG_HOME=" .. sh(base_env.XDG_CONFIG_HOME) ..
    " PATH=" .. sh(base_env.PATH) .. " " .. table.concat(words, " "))
  assert(code == 0, table.concat({ ... }, " ") .. ": " .. err)
end

test("records: the session of a worktree wt removed can be adopted by another checkout", function()
  answers = { "my-app", { text = "gone-a" }, 1 }
  I.worktree_run({})
  local dir, mine = wt .. "/gone-a", selected()
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "gone-a")
  assert(not exists(dir) and remembered(dir) == mine.session_id)
  mine.cwd, mine.attached = repo, true
  close(nil, remembered(repo))
  again()
  answers = { "my-app", 1 }
  I.switch_run({ session_id = mine.session_id, block_id = mine.block_id })
  assert(created() == 0 and selected() == mine, "the session is adopted")
  assert(remembered(repo) == mine.session_id and record(dir) == nil, "the stale record is dropped")
end)

test("records: a worktree wt removed opens again, and Clean Up then closes nothing", function()
  answers = { "my-app", { text = "gone-b" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/gone-b", selected().session_id
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "--no-delete-branch", "gone-b")
  again()
  answers = { "my-app", "gone-b" }
  I.worktree_run({})
  assert(selected().cwd == dir and exists(dir) and branch_of(dir) == "gone-b")
  assert(selected().session_id == id and created() == 0, "the same session, no new one")
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "--no-delete-branch", "gone-b")
  again()
  answers = { "my-app", "gone-b" }
  I.clean_up({})
  assert(not has_branch(repo, "gone-b"))
  assert(#calls == 0 and session(nil, id), "nothing is closed")
  assert(remembered(dir) == id, "no worktree held the branch, so no record was reached")
  close(nil, id)
end)

test("records: after git switch in a worktree, and a session closed by hand, it opens", function()
  answers = { "my-app", { text = "sw-a" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/sw-a", selected().session_id
  in_terminal(dir, "git", "switch", "-q", "-c", "sw-b")
  again()
  answers = { "my-app", "sw-b" }
  I.worktree_run({})
  assert(selected().session_id == id and created() == 0, "the folder's session")
  close(nil, id)
  again()
  answers = { "my-app", "sw-b" }
  I.worktree_run({})
  local s = selected()
  assert(s.cwd == dir and s.session_id ~= id and created() == 1)
  assert(remembered(dir) == s.session_id and record(dir).created == true, "the new one is kept")
  in_terminal(repo, "git", "switch", "-q", "shared")
  again()
  answers = { "my-app", "main" }
  I.switch_run({})
  assert(branch_of(repo) == "main" and selected().session_id == remembered(repo))
  git(repo, "worktree", "remove", dir)
  git(repo, "branch", "-q", "-D", "sw-a", "sw-b")
  close(nil, s.session_id)
end)

-- in_file says whether the saved state holds a record for dir, read from the
-- file itself, not from the state a load made.
local function in_file(dir)
  local text = read(tmp .. "/state/projects.json")
  local sessions = text and json.decode(text).sessions
  return type(sessions) == "table" and sessions[dir] ~= nil
end

test("records: Clean Up of a worktree whose folder was deleted closes the session it made", function()
  answers = { "my-app", { text = "gone-c" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/gone-c", selected().session_id
  assert(record(dir).created == true and in_file(dir))
  os.execute("rm -rf " .. sh(dir))
  again()
  answers = { "my-app", "gone-c" }
  I.clean_up({})
  assert(not has_branch(repo, "gone-c"))
  assert(session(nil, id) == nil and calls[#calls][1] == "session.destroy", "the session is closed")
  assert(not in_file(dir), "the record is gone from the file")
end)

test("records: Clean Up of a worktree whose folder was deleted leaves an adopted session open", function()
  answers = { "my-app", { text = "gone-d" }, 1 }
  I.worktree_run({})
  local dir, made = wt .. "/gone-d", selected().session_id
  close(nil, made)
  local mine = open_session(nil, "mine", dir)
  mine.attached = true
  again()
  answers = { "my-app", "gone-d" }
  I.worktree_run({ session_id = mine.session_id, block_id = mine.block_id })
  assert(selected() == mine and record(dir).created == false and in_file(dir), "adopted")
  os.execute("rm -rf " .. sh(dir))
  again()
  answers = { "my-app", "gone-d" }
  I.clean_up({})
  assert(not has_branch(repo, "gone-d"))
  assert(#calls == 0 and session(nil, mine.session_id) == mine, "the adopted session stays open")
  assert(not in_file(dir), "the record is gone from the file")
  close(nil, mine.session_id)
end)

test("records: Clean Up after the folder was deleted and the session closed by hand closes nothing", function()
  answers = { "my-app", { text = "gone-e" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/gone-e", selected().session_id
  close(nil, id)
  os.execute("rm -rf " .. sh(dir))
  again()
  answers = { "my-app", "gone-e" }
  I.clean_up({})
  assert(not has_branch(repo, "gone-e"))
  for _, c in ipairs(calls) do assert(c[1] ~= "session.destroy", "nothing is closed") end
  assert(record(dir) == nil, "the record is forgotten")
end)

test("records: a record whose created is not a boolean is ignored, and its session stays open", function()
  answers = { "my-app", { text = "odd-a" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/odd-a", selected().session_id
  I.load_state().sessions[dir] = { session = id, created = "false" }
  I.save_state()
  I.reset()
  assert(exists(dir) and record(dir) == nil, "the record is not used")
  again()
  answers = { "my-app", "odd-a" }
  I.clean_up({})
  assert(not exists(dir) and not has_branch(repo, "odd-a"))
  assert(#calls == 0 and session(nil, id), "its session stays open")
  close(nil, id)
end)

-- closes runs close_project_session for path, as wt's post-remove hook does.
-- ctx names another host, which the action must not reach.
local function closes(path)
  actions.close_project_session.run({ server = "studio" }, { path = path })
  for _, c in ipairs(calls) do assert(c[3] == nil, c[1] .. " went to another server") end
end

test("records: wt remove in a terminal, then the hook, closes the session it made", function()
  assert(actions.close_project_session.category == "Internal")
  answers = { "my-app", { text = "hook-a" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/hook-a", selected().session_id
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-a")
  assert(not exists(dir) and in_file(dir))
  again()
  closes(dir)
  assert(session(nil, id) == nil and calls[#calls][1] == "session.destroy", "the session is closed")
  assert(record(dir) == nil and not in_file(dir), "the record is gone")
  again()
  closes(dir)
  assert(#calls == 0, "a second call does nothing")
end)

test("records: the hook leaves an adopted session open and forgets its record", function()
  answers = { "my-app", { text = "hook-b" }, 1 }
  I.worktree_run({})
  local dir, made = wt .. "/hook-b", selected().session_id
  close(nil, made)
  local mine = open_session(nil, "mine", dir)
  mine.attached = true
  again()
  answers = { "my-app", "hook-b" }
  I.worktree_run({ session_id = mine.session_id, block_id = mine.block_id })
  assert(selected() == mine and record(dir).created == false)
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-b")
  again()
  closes(dir)
  assert(#calls == 0 and session(nil, mine.session_id) == mine, "the adopted session stays open")
  assert(record(dir) == nil and not in_file(dir), "the record is forgotten")
  close(nil, mine.session_id)
end)

test("records: the hook for a path with no record, or none, changes nothing", function()
  local file = tmp .. "/state/projects.json"
  local before = read(file)
  closes(tmp .. "/never-opened")
  closes("")
  closes("  ")
  closes(nil)
  actions.close_project_session.run({}, nil)
  assert(#calls == 0 and read(file) == before)
end)

test("records: after a restart, a gone folder's record is still there for the hook", function()
  answers = { "my-app", { text = "hook-c" }, 1 }
  I.worktree_run({})
  local dir, id = wt .. "/hook-c", selected().session_id
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-c")
  local before = read(tmp .. "/state/projects.json")
  I.reset()
  assert(record(dir).session == id and in_file(dir), "kept on load")
  assert(read(tmp .. "/state/projects.json") == before, "the load writes nothing")
  again()
  closes(dir)
  assert(session(nil, id) == nil and record(dir) == nil)
end)

test("records: the hook finds the record through a symbolic link, folder there or gone", function()
  local link = tmp .. "/wt-link"
  os.execute("ln -s " .. sh(tmp .. "/wt") .. " " .. sh(link))
  answers = { "my-app", { text = "hook-d" }, 1 }
  I.worktree_run({})
  local id = selected().session_id
  again()
  closes(link .. "/my-app/hook-d/")
  assert(session(nil, id) == nil and record(wt .. "/hook-d") == nil, "closed, folder there")
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-d")
  again()
  answers = { "my-app", { text = "hook-e" }, 1 }
  I.worktree_run({})
  id = selected().session_id
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-e")
  again()
  closes(link .. "/my-app/hook-e")
  assert(session(nil, id) == nil and record(wt .. "/hook-e") == nil, "closed, folder gone")
  os.remove(link)
end)

test("records: a worktree folder set through a link is kept by git's spelling, for the hook", function()
  local link = tmp .. "/wt-via"
  os.execute("ln -s " .. sh(tmp .. "/wt") .. " " .. sh(link))
  P.setup{ worktrees = link }
  answers = { "my-app", { text = "hook-f" }, 1 }
  I.worktree_run({})
  local id = selected().session_id
  assert(record(wt .. "/hook-f") ~= nil, "kept by git's spelling")
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "hook-f")
  again()
  closes(link .. "/my-app/hook-f")
  assert(session(nil, id) == nil and record(wt .. "/hook-f") == nil, "closed through the link")
  P.setup{ worktrees = tmp .. "/wt" }
  os.remove(link)
end)

test("a session that cannot be made ends Open Worktree with projects: and the reason", function()
  create_fails = "boom"
  local message, logged = ends({ "my-app", { text = "boom-a" }, 1 }, I.worktree_run, {})
  create_fails = nil
  assert(message == "projects: boom", message)
  assert(created() == 1 and #logged == 0, "no layout, so no second try")
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "boom-a")
end)

test("a session refused with a layout's windows and with one shell tab ends with the reason", function()
  create_fails = "boom"
  P.setup{ layout = function(t) return { { window_label = "x", layout = { options = { cwd = t.dir } } } } end }
  local message, logged = ends({ "my-app", { text = "boom-c" }, 1 }, I.worktree_run, {})
  P.setup{ layout = false }
  create_fails = nil
  assert(message == "projects: boom", message)
  assert(created() == 2 and #logged == 1, created() .. " creates, " .. #logged .. " lines")
  assert(logged[1]:find("refused the session with the layout function's windows: boom; trying one shell tab", 1, true),
    logged[1])
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "boom-c")
end)

test("a session that cannot be made is shown on one line", function()
  create_fails = "  session\n  limit   reached \n"
  answers = { "my-app", { text = "boom-b" }, 1 }
  local message = refused(I.worktree_run, {})
  create_fails = nil
  assert(message == "projects: session limit reached", message)
  in_terminal(repo, "wt", "remove", "--foreground", "--no-hooks", "boom-b")
end)

---------------------------------------------------------------------------
-- Clean-up
---------------------------------------------------------------------------

test("clean-up: the list is the worktrees and the regular branches, without the current one", function()
  local rows = I.backend.cleanup_rows{ project = repo }.rows
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
  assert(record(dir).created == true, "a session rex-projects made")
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

test("clean-up: uncommitted changes are refused with wt's words, and nothing changes", function()
  local dir = wt .. "/pr-1"
  local id = remembered(dir)
  write(dir .. "/new.txt", "x")
  answers = { "my-app", "pr-1" }
  local message = refused(I.clean_up, {})
  assert(message:find("^Cannot remove worktree: pr%-1 has uncommitted changes%. "), message)
  assert(exists(dir .. "/new.txt") and has_branch(repo, "pr-1") and session(nil, id), "an untracked file")
  os.remove(dir .. "/new.txt")
  write(dir .. "/f", "changed\n")
  again()
  answers = { "my-app", "pr-1" }
  message = refused(I.clean_up, {})
  assert(message:find("^Cannot remove worktree: pr%-1 has uncommitted changes%. "), message)
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
  assert(message:find("^Cannot remove worktree: pr%-1 has uncommitted changes%. "), message)
  assert(exists(dir .. "/new.txt") and has_branch(repo, "pr-1") and session(nil, id), "nothing changed")
  os.remove(dir .. "/new.txt")
end)

test("clean-up: run from a worktree's adopted session, Keep keeps the branch and the session", function()
  local dir = wt .. "/feat-x"
  commit(dir, "g", "work\n", "work")
  local id = remembered(dir)
  local mine = session(nil, id)
  assert(record(dir).created == false and mine.label == "my-app · feat/x", "adopted earlier")
  answers = { "my-app", "feat/x", "Keep" }
  I.clean_up({ session_id = id, block_id = mine.block_id })
  local offer = asked[3]
  assert(offer.title == "feat/x has changes that the default branch lacks", offer.title)
  assert(offer.items[2].subtitle == "wt remove -D feat/x", offer.items[2].subtitle)
  assert(#offer.items == 2 and offer.items[1].title == "Keep", "Keep is first")
  assert(not exists(dir), "the worktree stays removed")
  assert(has_branch(repo, "feat/x"), "the branch and its commits stay")
  assert(session(nil, id) == mine and mine.label == "my-app · feat/x", "the adopted session stays, named")
  assert(record(dir) == nil, "its record is forgotten")
  for _, c in ipairs(calls) do assert(c[1] ~= "session.destroy", "nothing is closed") end
  close(nil, id)
end)

test("clean-up: the session rex-projects made for a worktree is closed while the action waits", function()
  answers = { "my-app", { text = "keepme" }, 1 }
  I.worktree_run({})
  local dir = wt .. "/keepme"
  local id = remembered(dir)
  assert(record(dir).created == true)
  commit(dir, "g", "work\n", "work")
  again()
  answers = { "my-app", "keepme", function()
    -- The session goes last, after anything more is asked.
    assert(session(nil, id), "the session is open while the offer shows")
    return "Keep"
  end }
  I.clean_up({})
  assert(not exists(dir) and has_branch(repo, "keepme"))
  assert(session(nil, id) == nil, "the worktree's session is closed")
  assert(calls[#calls][1] == "session.destroy")
  git(repo, "branch", "-q", "-D", "keepme")
end)

test("clean-up: accepting the offer deletes the branch with -D", function()
  local _, at = cleanup_branches()
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

-- unmerged opens a worktree for a new branch, with a session rex-projects
-- makes, and gives it a commit the default branch lacks. It returns the
-- worktree's folder and the session's id.
local function unmerged(name)
  answers = { "my-app", { text = name }, 1 }
  I.worktree_run({})
  local dir = wt .. "/" .. name:gsub("/", "-")
  assert(record(dir).created == true)
  commit(dir, "g", "work\n", "work")
  again()
  return dir, remembered(dir)
end

test("clean-up: Force delete removes the branch of a worktree rex-projects made, and its session", function()
  local dir, id = unmerged("forceme")
  answers = { "my-app", "forceme", "Force delete" }
  I.clean_up({})
  assert(asked[3].title == "forceme has changes that the default branch lacks", asked[3].title)
  assert(not exists(dir) and not has_branch(repo, "forceme"))
  assert(session(nil, id) == nil, "the worktree's session is closed")
end)

test("clean-up: a cancelled or failed offer keeps the branch and still closes the session", function()
  local dir, id = unmerged("offer")
  local err, logged = ends({ "my-app", "offer" }, I.clean_up, {})
  assert(err == nil and #logged == 0 and #asked == 3, tostring(err))
  assert(not exists(dir) and has_branch(repo, "offer") and session(nil, id) == nil)
  git(repo, "branch", "-q", "-D", "offer")

  dir, id = unmerged("offer")
  err = ends({ "my-app", "offer", { why = "the palette\n broke " } }, I.clean_up, {})
  assert(err == "the palette broke", tostring(err))
  assert(not exists(dir) and has_branch(repo, "offer") and session(nil, id) == nil)
  git(repo, "branch", "-q", "-D", "offer")
end)

test("clean-up: a branch wt keeps for good is said after the session is closed", function()
  answers = { "my-app", { text = "hold/x" }, 1 }
  I.worktree_run({})
  local dir = wt .. "/hold-x"
  local id = remembered(dir)
  assert(record(dir).created == true)
  again()
  -- Git cannot delete a ref in a folder it cannot write to.
  local refs = git(repo, "rev-parse", "--git-path", "refs/heads/hold")
  if refs:sub(1, 1) ~= "/" then refs = repo .. "/" .. refs end
  os.execute("chmod a-w " .. sh(refs))
  answers = { "my-app", "hold/x" }
  local ok, message = pcall(I.clean_up, {})
  os.execute("chmod u+w " .. sh(refs))
  assert(not ok, "the action was refused")
  assert(message == "wt kept hold/x: git could not delete it", tostring(message))
  assert(not exists(dir) and has_branch(repo, "hold/x"), "the worktree goes, the branch stays")
  assert(session(nil, id) == nil and record(dir) == nil, "the session is closed")
  git(repo, "branch", "-q", "-D", "hold/x")
end)

-- opened opens a worktree for a new branch with nothing to merge, with a
-- session rex-projects makes, and returns its folder and the session's id.
local function opened(name)
  answers = { "my-app", { text = name }, 1 }
  I.worktree_run({})
  local dir = wt .. "/" .. name:gsub("/", "-")
  again()
  return dir, remembered(dir)
end

test("clean-up: hooks run whatever the branch's config holds, and so does opening it", function()
  local dir = opened("rm-own")
  git(repo, "branch", "rm-marked")
  -- An old rex-pr line is left as it is, and nothing reads it.
  git(repo, "config", "branch.rm-marked.rex-pr", "5")
  with_hooks(logging_hooks, function()
    local from = #wt_argv
    answers = { "my-app", "rm-own" }
    I.clean_up({})
    local runs = wt_runs(from, "remove")
    assert(#runs == 1 and not holds(runs[1], "--no-hooks") and not holds(runs[1], "--yes"),
      table.concat(runs[1] or {}, " "))
    assert(ran("remove rm-own"), "the user's pre-remove hook ran: " .. tostring(read(hook_log)))
    assert(not exists(dir) and not has_branch(repo, "rm-own"))

    again()
    from = #wt_argv
    answers = { "my-app", { text = "rm-marked" } }
    I.worktree_run({})
    runs = wt_runs(from, "switch")
    assert(#runs == 1 and not holds(runs[1], "--no-hooks"), table.concat(runs[1] or {}, " "))
    assert(ran("start rm-marked"), "the pre-start hook ran")
    again()
    from = #wt_argv
    answers = { "my-app", "rm-marked" }
    I.clean_up({})
    runs = wt_runs(from, "remove")
    assert(#runs == 1 and not holds(runs[1], "--no-hooks"), table.concat(runs[1] or {}, " "))
    assert(ran("remove rm-marked"), "the pre-remove hook ran")
    assert(not exists(wt .. "/rm-marked") and not has_branch(repo, "rm-marked"))
  end)
end)

test("clean-up: a project hook that needs approval stops it, and nothing changes", function()
  local dir, id = opened("rm-ask")
  os.execute("mkdir -p " .. sh(repo .. "/.config"))
  write(repo .. "/.config/wt.toml", '[pre-remove]\nmark = "touch ../removed"\n')
  answers = { "my-app", "rm-ask" }
  local message = refused(I.clean_up, {})
  os.execute("rm -rf " .. sh(repo .. "/.config"))
  local tail = "pre-remove mark: touch ../removed. wt cannot ask for approval without a terminal: " ..
    "run wt config approvals add in a terminal in " .. I.short(repo) .. ", then try again"
  assert(message:sub(-#tail) == tail, message)
  assert(exists(dir) and has_branch(repo, "rm-ask") and session(nil, id) and remembered(dir) == id, "nothing changed")
  again()
  answers = { "my-app", "rm-ask" }
  I.clean_up({})
  assert(not exists(dir) and session(nil, id) == nil)
end)

test("clean-up: a worktree wt removed before it failed has its session closed, with no offer", function()
  local dir, id = unmerged("rm-fail")
  intercept = function(argv, opts, real)
    if argv[4] ~= "remove" then return nil end
    real(argv, opts)
    return { ok = false, code = 1, stdout = "", stderr = "✗ the disk broke\n" }
  end
  answers = { "my-app", "rm-fail" }
  local ok, message = pcall(I.clean_up, {})
  intercept = nil
  assert(not ok and message == "the disk broke", tostring(message))
  assert(#asked == 2, "no Force delete offer")
  assert(not exists(dir) and session(nil, id) == nil and record(dir) == nil, "closed and forgotten")
  git(repo, "branch", "-q", "-D", "rm-fail")
end)

test("clean-up: wt saying deleted while git still lists the worktree keeps its record and session", function()
  local dir, id = opened("rm-stays")
  intercept = function(argv)
    if argv[4] ~= "remove" then return nil end
    return { ok = true, code = 0, stderr = "", stdout = '[{"kind":"worktree","branch":"rm-stays","path":"' ..
      dir .. '","branch_outcome":"deleted"}]' }
  end
  local err = ends({ "my-app", "rm-stays" }, I.clean_up, {})
  intercept = nil
  assert(err == nil, tostring(err))
  assert(exists(dir) and session(nil, id) and remembered(dir) == id, "the record and the session stay")
  for _, c in ipairs(calls) do assert(c[1] ~= "session.destroy", "nothing is closed") end
  again()
  answers = { "my-app", "rm-stays" }
  I.clean_up({})
  assert(not exists(dir) and session(nil, id) == nil)
end)

test("clean-up: when a hook closed the session first, Clean Up asks as before and closes nothing more", function()
  local dir, id = unmerged("rm-hook")
  local first = true
  intercept = function(argv, opts, real)
    if argv[4] ~= "remove" or not first then return nil end
    first = false
    local r = real(argv, opts)
    -- As the post-remove hook in the README does.
    actions.close_project_session.run({}, { path = dir })
    return r
  end
  answers = { "my-app", "rm-hook", "Force delete" }
  I.clean_up({})
  intercept = nil
  assert(asked[3] and asked[3].title == "rm-hook has changes that the default branch lacks", "the offer")
  assert(not exists(dir) and not has_branch(repo, "rm-hook") and session(nil, id) == nil and record(dir) == nil)
  local destroyed = 0
  for _, c in ipairs(calls) do if c[1] == "session.destroy" then destroyed = destroyed + 1 end end
  assert(destroyed == 1, "closed once, by the hook: " .. destroyed)
end)

test("clean-up: a worktree that only Force delete removes has its session closed", function()
  local dir, id = unmerged("rm-late")
  intercept = function(argv)
    if argv[4] ~= "remove" or holds(argv, "-D") then return nil end
    return { ok = true, code = 0, stderr = "", stdout = '[{"kind":"worktree","branch":"rm-late","path":"' ..
      dir .. '","branch_outcome":"retained_unmerged"}]' }
  end
  answers = { "my-app", "rm-late", "Force delete" }
  I.clean_up({})
  intercept = nil
  assert(asked[3] and asked[3].title == "rm-late has changes that the default branch lacks", "the offer")
  assert(not exists(dir) and not has_branch(repo, "rm-late"))
  assert(session(nil, id) == nil and record(dir) == nil, "the session is closed")
end)

test("clean-up: a Force delete git cannot finish says so, the worktree gone and its session closed", function()
  local dir, id = unmerged("v2/x")
  local refs = git(repo, "rev-parse", "--git-path", "refs/heads/v2")
  if refs:sub(1, 1) ~= "/" then refs = repo .. "/" .. refs end
  answers = { "my-app", "v2/x", function()
    os.execute("chmod a-w " .. sh(refs))
    return "Force delete"
  end }
  local ok, message = pcall(I.clean_up, {})
  os.execute("chmod u+w " .. sh(refs))
  assert(not ok and message == "wt kept v2/x: git could not delete it", tostring(message))
  assert(not exists(dir) and has_branch(repo, "v2/x"), "the worktree goes, the branch stays")
  assert(session(nil, id) == nil and record(dir) == nil, "the session is closed")
  git(repo, "branch", "-q", "-D", "v2/x")
end)

---------------------------------------------------------------------------
-- How an action ends
---------------------------------------------------------------------------

test("a cancelled list ends any action quietly, and a failed one says why", function()
  local steps = {
    { "Switch Branch: project", I.switch_run, {} },
    { "Switch Branch: project, from Add project", I.switch_run, { "Add project…" } },
    { "Switch Branch: branch", I.switch_run, { "my-app" } },
    { "Switch Branch: base", I.switch_run, { "my-app", { text = "not-yet" } } },
    { "Open Worktree: project", I.worktree_run, {} },
    { "Open Worktree: branch", I.worktree_run, { "my-app" } },
    { "Open Worktree: base", I.worktree_run, { "my-app", { text = "not-yet" } } },
    { "Clean Up: project", I.clean_up, {} },
    { "Clean Up: branch", I.clean_up, { "my-app" } },
    { "Add Project", I.add_run, {} },
    { "Remove Project", I.remove_run, {} },
  }
  local before = git(repo, "for-each-ref", "--format=%(refname)")
  for _, step in ipairs(steps) do
    local name, f, list = step[1], step[2], step[3]
    again()
    local err, logged = ends(list, f, {})
    assert(err == nil, name .. " cancelled: " .. tostring(err))
    assert(#logged == 0, name .. " cancelled logged: " .. table.concat(logged, "; "))
    assert(#asked == #list + 1, name .. ": asked " .. #asked)
    again()
    local failing = { unpack(list) }
    failing[#failing + 1] = { why = "palette broke" }
    err, logged = ends(failing, f, {})
    assert(err == "palette broke", name .. " failed: " .. tostring(err))
    assert(#logged == 0, name .. " failed logged: " .. table.concat(logged, "; "))
    again()
    failing[#failing] = { why = false }
    err = ends(failing, f, {})
    assert(err == nil, name .. " with no reason: " .. tostring(err))
  end
  assert(created() == 0 and #queued == 0, "nothing was opened")
  assert(git(repo, "for-each-ref", "--format=%(refname)") == before, "no branch changed")
  assert(branch_of(repo) == "main")
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
  local rows = I.backend.here_rows{ project = big }.rows
  assert(#rows == 2000, "rows: " .. #rows)
  local list, at = ids(rows)
  assert(list[1] == "main" and at["origin/b0001"] == 2, "the local branch origin/b0001 is listed once")
  local seen = {}
  for _, id in ipairs(list) do assert(not seen[id], id); seen[id] = true end
  assert(#I.backend.name{ project = big, name = "new" }.rows == 2000)
  -- A branch that fell off the end of the list can still be typed.
  assert(not at["origin/b2100"])
  local r = I.backend.switch_here{ project = big, name = "origin/b2100" }
  assert(r.dir == big and branch_of(big) == "b2100", tostring(r.why))
end)

---------------------------------------------------------------------------
-- Pull requests in Open Worktree
---------------------------------------------------------------------------

-- The pull requests live in up as refs/pull/<n>/head, as on GitHub. #9 is a
-- branch of up, review-me; #8 comes from contrib/fork's branch fork-fix.
-- gh names up as https://github.com/remotes/up, the address of origin.
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

-- open_pr types typed into Open Worktree in my-app and returns the session
-- shown.
local function open_pr(typed, ctx)
  answers = { "my-app", { text = typed } }
  I.worktree_run(ctx or {})
  return selected()
end

test("worktree: pr:N with a project hook not approved fails with wt's words, and nothing changes", function()
  git(up, "switch", "-q", "-c", "review-me")
  commit(up, "r", "one\n", "review one")
  git(up, "switch", "-q", "main")
  git(fork, "switch", "-q", "-c", "fork-fix")
  commit(fork, "k", "fork\n", "fork fix")
  git(up, "fetch", "-q", fork, "fork-fix:refs/pull/8/head")
  prs = { pull(9, "Review me", "review-me", false, "ana"), pull(8, "Fix from a fork", "fork-fix", true, "bo") }
  publish(9, "review-me")
  prs[2].headRefOid = git(up, "rev-parse", "refs/pull/8/head")

  os.execute("mkdir -p " .. sh(repo .. "/.config"))
  write(repo .. "/.config/wt.toml", '[pre-start]\nmark = "touch hook-ran"\n')
  answers = { "my-app", { text = "pr:9" } }
  local message = refused(I.worktree_run, {})
  os.execute("rm -rf " .. sh(repo .. "/.config"))
  local tail = "pre-start mark: touch hook-ran. wt cannot ask for approval without a terminal: " ..
    "run wt config approvals add in a terminal in " .. I.short(repo) .. ", then try again"
  assert(message:sub(-#tail) == tail, message)
  assert(created() == 0 and #queued == 0 and not has_branch(repo, "review-me") and not exists(review_dir),
    "nothing made")
end)

test("worktree: pr:N opens the pull request's worktree with the project's hooks, labelled by its number", function()
  local s
  with_hooks(logging_hooks, function()
    local from = #wt_argv
    s = open_pr("pr:9")
    local runs = wt_runs(from, "switch")
    assert(#runs == 1 and runs[1][#runs[1]] == "pr:9" and not holds(runs[1], "--no-hooks"),
      table.concat(runs[1] or {}, " "))
    assert(ran("start review-me"), "the hook ran: " .. tostring(read(hook_log)))
  end)
  assert(#asked == 2, "no base")
  assert(s.cwd == review_dir and s.label == "my-app · #9", s.cwd .. " · " .. s.label)
  assert(branch_of(review_dir) == "review-me")
  assert(git(review_dir, "rev-parse", "HEAD") == git(up, "rev-parse", "review-me"))
  assert(git(repo, "rev-parse", "--abbrev-ref", "review-me@{upstream}") == "origin/review-me", "it follows the remote branch")
  assert(select(2, try(repo, "config", "--get", "branch.review-me.rex-pr")) ~= 0, "no mark")
  -- Again: the same session, and nothing made.
  again()
  assert(open_pr("pr:9") == s and created() == 0 and #asked == 2)
end)

test("worktree: a pull request from a fork gets its branch's name, and pushes to the fork", function()
  local from = #wt_argv
  local s = open_pr("https://github.com/remotes/up/pull/8")
  local dir = wt .. "/fork-fix"
  assert(s.cwd == dir and s.label == "my-app · #8", s.cwd .. " · " .. s.label)
  local runs = wt_runs(from, "switch")
  assert(#runs == 1 and runs[1][#runs[1]] == "pr:8", "the link goes to wt as pr:8")
  assert(branch_of(dir) == "fork-fix")
  assert(git(dir, "rev-parse", "HEAD") == git(fork, "rev-parse", "fork-fix"))
  assert(git(repo, "config", "--get", "branch.fork-fix.merge") == "refs/pull/8/head", "it follows the pull request")
  assert(git(repo, "config", "--get", "branch.fork-fix.pushRemote") == "https://github.com/contrib/fork.git",
    "and pushes to the fork")
end)

test("worktree: a link to one of the project's remotes opens as pr:N, any other is refused before wt", function()
  for _, link in ipairs({ "https://github.com/remotes/up/pull/9/files", "https://GitHub.com/Remotes/Up/pull/9" }) do
    again()
    local from = #wt_argv
    assert(open_pr(link).cwd == review_dir, link)
    local runs = wt_runs(from, "switch")
    assert(#runs == 1 and runs[1][#runs[1]] == "pr:9", link .. ": " .. table.concat(runs[1] or {}, " "))
  end
  for link, why in pairs({
    ["https://github.example.com/remotes/up/pull/9"] =
      "that link is to a pull request of github.example.com/remotes/up, which is no remote of my-app",
    ["https://github.com/other/thing/pull/9"] =
      "that link is to a pull request of github.com/other/thing, which is no remote of my-app",
  }) do
    again()
    local from = #wt_argv
    answers = { "my-app", { text = link } }
    local message = refused(I.worktree_run, {})
    assert(message == why, message)
    assert(#wt_argv == from, link .. ": wt did not run")
    assert(#queued == 0 and created() == 0)
  end
end)

test("worktree: a link matches a remote by host and owner/repo, and an ssh alias by owner/repo", function()
  local acme = tmp .. "/code/acme"
  os.execute("mkdir -p " .. sh(acme))
  git(acme, "init", "-q", "-b", "main")
  commit(acme, "f", "x\n", "init")
  local switched
  intercept = function(argv)
    if argv[4] ~= "switch" then return nil end
    switched = argv[#argv]
    return { ok = false, code = 1, stdout = "", stderr = "stopped by the test" }
  end
  local function open(remotes, link)
    for _, name in ipairs({ "origin", "other" }) do try(acme, "remote", "remove", name) end
    for name, url in pairs(remotes) do git(acme, "remote", "add", name, url) end
    switched = nil
    return I.backend.open_worktree{ project = acme, name = link }
  end
  local ok, err = pcall(function()
    local link = "https://github.example.com/acme/app/pull/5"
    for _, case in ipairs({
      { "https://github.example.com/acme/app.git", link },
      { "git@github.example.com:acme/app.git", link },
      { "git@github.example.com:acme/app.git", link .. "/files" },
      { "ssh://git@github.example.com:2222/acme/app/", link },
      { "https://github.example.com:8443/acme/app", link },
      { "git@work:acme/app.git", link },
      { "https://github.example.com/acme/app.git", "https://GitHub.example.com/Acme/App/pull/5" },
    }) do
      local r = open({ origin = case[1] }, case[2])
      assert(switched == "pr:5" and r.dir == nil, case[1] .. " " .. case[2] .. ": " .. tostring(switched))
    end
    -- Any one remote will do.
    open({ origin = "https://github.com/x/y.git", other = "git@github.example.com:acme/app.git" }, link)
    assert(switched == "pr:5", "the second remote")
    local r = open({ origin = "https://github.example.com/acme/app.git" }, "https://github.com/acme/app/pull/5")
    assert(switched == nil and r.why == "that link is to a pull request of github.com/acme/app, " ..
      "which is no remote of acme", tostring(r.why))
    -- A folder is no host, not an ssh alias.
    r = open({ origin = "file:///srv/git/acme/app.git" }, link)
    assert(switched == nil and r.why == "that link is to a pull request of github.example.com/acme/app, " ..
      "which is no remote of acme", tostring(r.why))
    r = open({ origin = "git@github.example.com:acme/app.git" }, "https://github.example.com/other/thing/pull/5")
    assert(switched == nil and r.why == "that link is to a pull request of github.example.com/other/thing, " ..
      "which is no remote of acme", tostring(r.why))
    -- A remote is read as written: insteadOf does not make it another.
    open({ origin = "https://github.example.com/acme/app.git" }, link)
    git(acme, "config", "url.https://elsewhere.example.com/.insteadOf", "https://github.example.com/")
    open({ origin = "https://github.example.com/acme/app.git" }, link)
    assert(switched == "pr:5", "insteadOf is not applied")
  end)
  intercept = nil
  os.execute("rm -rf " .. sh(acme))
  if not ok then error(err, 0) end
  local host, path = I.repo_of("git@gh-work:Acme/App.git")
  assert(host == "gh-work" and path == "acme/app")
  host, path = I.repo_of("ssh://git@github.com:22/acme/app/")
  assert(host == "github.com" and path == "acme/app")
  assert(I.repo_of("/some/folder/app.git") == nil and I.repo_of("app") == nil)
  assert(I.repo_of("file:///srv/git/acme/app.git") == nil)
end)

test("worktree: a pull request that moved on is opened as it is, and nothing is asked", function()
  git(up, "switch", "-q", "review-me")
  commit(up, "r", "two\n", "review two")
  git(up, "switch", "-q", "main")
  publish(9, "review-me")
  local before = git(review_dir, "rev-parse", "HEAD")
  assert(open_pr("pr:9").cwd == review_dir and #asked == 2)
  assert(git(review_dir, "rev-parse", "HEAD") == before, "bringing it up to date is git's to do")
end)

test("worktree: a pull request's worktree that is gone is made again, and the main checkout's opens there", function()
  local id = remembered(review_dir)
  -- Removed with git.
  git(repo, "worktree", "remove", review_dir)
  local s = open_pr("pr:9")
  assert(s.cwd == review_dir and s.session_id == id and created() == 0)
  assert(branch_of(review_dir) == "review-me")
  -- Deleted by hand, so that git still lists it: wt says to prune it.
  os.execute("rm -rf " .. sh(review_dir))
  again()
  answers = { "my-app", { text = "pr:9" } }
  local message = refused(I.worktree_run, {})
  assert(message:find("^Worktree for review%-me is stale") and message:find("git worktree prune", 1, true), message)
  assert(#queued == 0)
  git(repo, "worktree", "prune")
  again()
  assert(open_pr("pr:9").session_id == id and branch_of(review_dir) == "review-me")
  -- In the main checkout it is the project's own session.
  local was = branch_of(repo)
  git(repo, "worktree", "remove", review_dir)
  git(repo, "switch", "-q", "review-me")
  again()
  s = open_pr("pr:9")
  assert(s.cwd == repo and s.label == "my-app", s.label)
  git(repo, "switch", "-q", was)
  again()
  assert(open_pr("pr:9").cwd == review_dir)
end)

test("worktree: a pull request run from a session in its worktree adopts it", function()
  close_kept(review_dir)
  I.load_state().sessions[review_dir] = nil
  I.save_state()
  local mine = open_session(nil, "somewhere", review_dir)
  mine.attached = true
  I.load_state().recent = { plain, repo }
  local s = open_pr("pr:9", { session_id = mine.session_id, block_id = mine.block_id })
  assert(asked[1].items[1].id == repo, "the focused project first: " .. asked[1].items[1].id)
  assert(created() == 0 and s == mine, "the session there is the worktree's")
  assert(mine.label == "my-app · #9" and remembered(review_dir) == mine.session_id, mine.label)
  assert(I.load_state().recent[1] == repo, "the project is first on the recent list")
end)

test("worktree: a pull request whose branch is there already opens it as it is", function()
  -- shared is a branch of the repository already, so #10 opens it.
  table.insert(prs, 1, pull(10, "Shared work", "shared", false, "cy"))
  publish(10, "shared")
  local tip, shared_dir = git(repo, "rev-parse", "shared"), wt .. "/shared"
  assert(branch_of(repo) ~= "shared" and not exists(shared_dir))
  local function open_it()
    again()
    local s = open_pr("pr:10")
    assert(#asked == 2, "nothing more is asked")
    assert(git(repo, "rev-parse", "shared") == tip, "the branch stays where it was")
    return s
  end
  -- Held by no checkout: a worktree for it.
  local s = open_it()
  assert(s.cwd == shared_dir and s.label == "my-app · #10" and branch_of(shared_dir) == "shared", s.label)
  -- Held by a worktree: that one.
  assert(open_it() == s and created() == 0)
  -- Held by the main checkout: the project's own session.
  local was = branch_of(repo)
  git(repo, "worktree", "remove", shared_dir)
  git(repo, "switch", "-q", "shared")
  s = open_it()
  assert(s.cwd == repo and s.label == "my-app", s.label)
  git(repo, "switch", "-q", was)
  assert(open_it().cwd == shared_dir)
  table.remove(prs, 1)
end)

test("worktree: a pull request wt cannot open is refused with wt's words, and nothing is made", function()
  answers = { "my-app", { text = "pr:77" } }
  local message = refused(I.worktree_run, {})
  assert(message:find("^PR #77 not found on remotes/up"), message)
  -- #5 is of a repository that is no remote.
  local p = pull(5, "From elsewhere", "elsewhere-fix", false, "di")
  p.url = "https://github.com/elsewhere/proj/pull/5"
  table.insert(prs, 1, p)
  local r = I.backend.open_worktree{ project = repo, name = "pr:5" }
  table.remove(prs, 1)
  assert(r.dir == nil and r.why:find("elsewhere/proj", 1, true), tostring(r.why))
  assert(not has_branch(repo, "elsewhere-fix") and not exists(wt .. "/elsewhere-fix"), "nothing was made")
  -- #11 was merged and its branch deleted: only the pull request is left.
  table.insert(prs, 1, pull(11, "Merged and gone", "gone-branch", false, "ed"))
  publish(11, "pr-1")
  r = I.backend.open_worktree{ project = repo, name = "pr:11" }
  table.remove(prs, 1)
  assert(r.dir == nil and r.why:find("gone-branch", 1, true), tostring(r.why))
  assert(not has_branch(repo, "gone-branch") and not exists(wt .. "/gone-branch"), "nothing was made")
  git(up, "update-ref", "-d", "refs/pull/11/head")
  assert(#queued == 0 and created() == 0)

  assert(I.pr_number("#12") == 12 and I.pr_number("https://github.com/o/r/pull/12/files") == 12)
  for _, link in ipairs({ "https://github.com/o/r/pull/12", "https://github.com/o/r/pull/12/",
    "https://github.com/o/r/pull/12/commits/0a1b2c3", "https://github.com/o/r/pull/12#issuecomment-1",
    "https://github.com/o/r/pull/12?diff=split" }) do
    assert(I.pr_number(link) == 12, link)
  end
  assert(I.pr_number("https://github.com/o/r/pulls") == nil and I.pr_number("12a") == nil)
end)

test("worktree: on another host a pull request opens there, with the network's time limit", function()
  relays, local_execs = 0, 0
  timeouts, envs = {}, {}
  answers = { "my-app", { text = "pr:8" } }
  I.worktree_run({ server = "studio" })
  assert(local_execs == 0 and relays >= 2, "ran there")
  assert(asked[1].title == "Open worktree on studio", asked[1].title)
  -- What uses the network: wt switch pr:<n>, which runs gh and git fetch.
  local limited = false
  for _, t in ipairs(timeouts) do
    assert(t.relayed and t.seconds >= 1 and t.seconds <= 8, tostring(t.seconds))
    assert(t.argv[1] == "wt" and t.argv[#t.argv] == "pr:8", "nothing else is: " .. table.concat(t.argv, " "))
    limited = true
  end
  assert(limited, "wt is limited")
  -- Every other wt command is kept off the network.
  local off = 0
  for _, e in ipairs(envs) do
    assert(e.relayed and e.argv[1] == "wt" and e.env.GIT_ALLOW_PROTOCOL == "none", table.concat(e.argv, " "))
    off = off + 1
  end
  assert(off >= 1, "wt found the default branch off the network")

  stalls = function(argv) return argv[1] == "wt" and argv[#argv] == "pr:8" end
  answers = { "my-app", { text = "pr:8" } }
  local message = refused(I.worktree_run, { server = "studio" })
  stalls = nil
  assert(message:find("^wt switch did not finish in the time") and
    message:find("open pr:8 again to go to the worktree wt made", 1, true), message)
end)

-- seen_by runs f with the label and layout settings recording the table
-- each one gets, and answering label and layout, or for nil what
-- rex-projects would use, then unsets them, also when f fails. It returns
-- what each one saw.
local function seen_by(label, layout, f)
  local seen = {}
  P.setup{
    label = function(t) seen.label = t; return label or t.label end,
    layout = function(t)
      seen.layout = t
      return layout or { { window_label = "shell", layout = { options = { cwd = t.dir, shell = t.shell } } } }
    end,
  }
  local ok, err = pcall(f)
  P.setup{ label = false, layout = false }
  if not ok then error(err, 0) end
  return seen
end

test("shaping: a pull request opened as a worktree tells its number", function()
  close_kept(review_dir)
  close_kept(wt .. "/fork-fix")
  local seen = seen_by("reviewing", nil, function() open_pr("pr:9") end)
  assert(seen.label.pr == 9 and seen.label.branch == "review-me" and seen.label.dir == review_dir,
    tostring(seen.label.pr) .. " " .. tostring(seen.label.branch))
  assert(seen.label.label == "my-app · #9" and selected().label == "reviewing")
  again()
  seen = seen_by(nil, nil, function() open_pr("https://github.com/remotes/up/pull/8") end)
  assert(seen.label.pr == 8 and seen.label.branch == "fork-fix" and seen.label.project == "my-app",
    tostring(seen.label.pr) .. " " .. tostring(seen.label.branch))
  assert(selected().label == "my-app · #8")
  -- In the main checkout, the project's own label and still the number.
  local was = branch_of(repo)
  close_kept(repo)
  git(repo, "worktree", "remove", review_dir)
  git(repo, "switch", "-q", "review-me")
  again()
  seen = seen_by(nil, nil, function() open_pr("pr:9") end)
  git(repo, "switch", "-q", was)
  assert(seen.label.pr == 9 and seen.label.dir == repo and seen.label.branch == "review-me",
    tostring(seen.label.pr) .. " " .. tostring(seen.label.dir))
  assert(seen.label.label == "my-app" and selected().cwd == repo)
  again()
  assert(open_pr("pr:9").cwd == review_dir, "the worktree is made again")
end)

test("clean-up: a pull request's branch goes with its worktree, and its hooks run", function()
  with_hooks(logging_hooks, function()
    for _, name in ipairs({ "review-me", "fork-fix" }) do
      again()
      local from = #wt_argv
      answers = { "my-app", name, "Force delete" }
      I.clean_up({})
      assert(not has_branch(repo, name), name)
      for _, argv in ipairs(wt_runs(from, "remove")) do
        assert(not holds(argv, "--no-hooks"), table.concat(argv, " "))
      end
      assert(ran("remove " .. name), name .. ": the pre-remove hook ran")
    end
  end)
end)

test("Review Pull Request and the code only it used are gone", function()
  local source = assert(read("projects.lua"))
  for _, word in ipairs({ "review_pull_request", "backend.pulls", "backend.review", "review_run", "gh(",
    "pr_branches", "set-default", "pr_mark", "--no-hooks", "switch_worktree(project, how" }) do
    assert(not source:find(word, 1, true), "projects.lua still holds " .. word)
  end
  assert(not source:find("rex%-pr[^o]"), "projects.lua still holds rex-pr")
  assert(actions.review_pull_request == nil and I.backend.pulls == nil and I.backend.review == nil)
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
  I.worktree_run({ server = "studio", session_id = mine.session_id, block_id = mine.block_id })
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
  I.switch_run({ server = "studio", session_id = mine.session_id, block_id = mine.block_id })
  assert(local_execs == 0 and created() == 0)
  assert(mine.label == "my-app" and remembered(repo) == mine.session_id and #queued == 0)
end)

test("another host: git's refusal arrives as git wrote it", function()
  relays, local_execs = 0, 0
  write(repo .. "/f", "mine\n")
  answers = { "my-app", "feat-login" }
  local message = refused(I.switch_run, { server = "studio" })
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

test("another host: a hook-running open has the network's time limit, and a stopped one opens again", function()
  timeouts, envs = {}, {}
  local seen
  intercept = function(argv, opts, real)
    if argv[4] ~= "switch" then return nil end
    seen = { argv = argv, opts = opts or {} }
    real(argv, opts)
    return stopped()
  end
  -- An existing branch skips new_base, so only wt_hooked asks for the
  -- default branch just before the switch.
  git(repo, "branch", "hook-slow")
  answers = { "my-app", { text = "hook-slow" } }
  local message = refused(I.worktree_run, { server = "studio" })
  intercept = nil
  assert(message:find("^wt switch did not finish in the time") and
    message:find("open hook-slow again to go to the worktree wt made", 1, true), message)
  assert(not holds(seen.argv, "--no-hooks"), "the user's own branch runs hooks")
  assert(seen.opts.timeout and seen.opts.timeout >= 1 and seen.opts.timeout <= 8, tostring(seen.opts.timeout))
  assert(not (seen.opts.env and seen.opts.env.GIT_ALLOW_PROTOCOL), "hooks keep the network")
  local before = wt_argv[#wt_argv - 1]
  assert(before[4] == "config" and before[6] == "default-branch", "the default branch first")
  local found = false
  for _, e in ipairs(envs) do
    if e.argv == before then found = e.env.GIT_ALLOW_PROTOCOL == "none" end
  end
  assert(found, "found off the network")
  assert(exists(wt .. "/hook-slow") and created() == 0, "wt made the worktree, and no session")

  again()
  local from = #wt_argv
  answers = { "my-app", { text = "hook-slow" } }
  I.worktree_run({ server = "studio" })
  assert(#wt_runs(from, "switch") == 0, "no second wt switch")
  assert(session("studio", remembered(wt .. "/hook-slow")).cwd == wt .. "/hook-slow")
end)

test("another host: a stopped clean-up closes the session exactly when the worktree is gone", function()
  local dir = wt .. "/hook-slow"
  local id = remembered(dir)
  intercept = function(argv) if argv[4] == "remove" then return stopped() end end
  answers = { "my-app", "hook-slow" }
  local message = refused(I.clean_up, { server = "studio" })
  intercept = nil
  assert(message:find("^wt remove did not finish in the time"), message)
  assert(exists(dir) and session("studio", id) and remembered(dir) == id, "still there: nothing closed")

  again()
  intercept = function(argv, opts, real)
    if argv[4] ~= "remove" then return nil end
    real(argv, opts)
    return stopped()
  end
  answers = { "my-app", "hook-slow" }
  message = refused(I.clean_up, { server = "studio" })
  intercept = nil
  assert(message:find("^wt remove did not finish in the time"), message)
  assert(not exists(dir) and session("studio", id) == nil and record(dir) == nil, "gone: the session is closed")
end)

test("a host without this file says so", function()
  remote_missing = true
  local ok, err = pcall(I.switch_run, { server = "studio" })
  remote_missing = false
  assert(not ok and err:find("^projects: studio: ") and err:find("init.lua on studio", 1, true), tostring(err))
end)

test("a relay error is shown on one line", function()
  remote_missing = "not_found:\n  no   action\tprojects_backend"
  local ok, err = pcall(I.switch_run, { server = "studio" })
  remote_missing = false
  assert(not ok and err == "projects: studio: not_found: no action projects_backend"
    .. " (is projects.lua in init.lua on studio?)", tostring(err))
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
  I.worktree_run({})
  assert(made_with().shell == "fish" and made_with().cwd == wt .. "/shell-one")
  -- false is the account's default shell again.
  again()
  P.setup{ shell = false }
  answers = { "my-app", { text = "shell-two" }, 1 }
  I.worktree_run({})
  assert(made_with().shell == nil and made_with().cwd == wt .. "/shell-two")
end)

---------------------------------------------------------------------------
-- The label and layout settings
---------------------------------------------------------------------------

-- warned returns the warnings among the lines logged.
local function warned(logged)
  local list = {}
  for _, line in ipairs(logged) do
    if line:find("^warn ") then list[#list + 1] = line end
  end
  return list
end

test("shaping: label names a new session from the table it is given", function()
  local seen
  P.setup{ shell = "fish", label = function(t) seen = t; return t.project .. " / " .. t.branch end }
  answers = { "my-app", { text = "shape-one" }, 1 }
  local err, logged = ends(answers, I.worktree_run, {})
  P.setup{ shell = false, label = false }
  assert(err == nil, err)
  local s = selected()
  assert(s.label == "my-app / shape-one" and s.cwd == wt .. "/shape-one", s.label)
  assert(seen.project == "my-app" and seen.branch == "shape-one" and seen.dir == wt .. "/shape-one")
  assert(seen.host == nil and seen.pr == nil and seen.shell == "fish" and seen.label == "my-app · shape-one")
  assert(#warned(logged) == 0)
end)

test("shaping: an adopted session gets the label, and no layout", function()
  close_kept(repo)
  local mine = open_session(nil, "quiet-meadow", repo)
  mine.attached = true
  local seen = seen_by("custom", { "never used" }, function()
    answers = { "my-app", 1 }
    I.switch_run({ session_id = mine.session_id, block_id = mine.block_id })
  end)
  assert(created() == 0 and selected() == mine and mine.label == "custom", mine.label)
  assert(seen.layout == nil, "layout is not called for an adopted session")
  assert(seen.label.branch == "main" and seen.label.dir == repo and seen.label.label == "my-app")
  assert(mine.windows == nil, "its windows are kept")
end)

test("shaping: a remembered session that lives is gone to, not relabelled", function()
  local id = remembered(repo)
  local seen = seen_by("again", nil, function()
    answers = { "my-app", 1 }
    I.switch_run({})
  end)
  assert(selected().session_id == id and selected().label == "custom" and seen.label == nil)
end)

test("shaping: layout gives a new session its windows, and each function its own table", function()
  local two = {
    { window_label = "edit", layout = { options = { cwd = wt .. "/shape-two" } } },
    { window_label = "run", layout = { options = { cwd = wt .. "/shape-two" } } },
  }
  local seen = {}
  P.setup{
    label = function(t) seen.label = t; t.dir = "changed"; return nil end,
    layout = function(t) seen.layout = t; return two end,
  }
  answers = { "my-app", { text = "shape-two" }, 1 }
  local err, logged = ends(answers, I.worktree_run, {})
  P.setup{ label = false, layout = false }
  assert(err == nil, err)
  local s = selected()
  assert(s.windows == two and #s.windows == 2, "both windows")
  assert(s.label == "my-app · shape-two", "a nil label is rex-projects' own: " .. s.label)
  assert(seen.layout.dir == wt .. "/shape-two" and seen.label ~= seen.layout, "a copy each")
  local w = warned(logged)
  assert(#w == 1 and w[1]:find("the label function", 1, true), table.concat(w, "; "))
end)

test("shaping: a label that fails or answers no string falls back with one warning", function()
  for i, f in ipairs({
    function() error("boom") end,
    function() return nil end,
    function() return 42 end,
  }) do
    again()
    P.setup{ label = f }
    answers = { "my-app", { text = "label-bad-" .. i }, 1 }
    local err, logged = ends(answers, I.worktree_run, {})
    P.setup{ label = false }
    assert(err == nil, err)
    local s = selected()
    assert(s.label == "my-app · label-bad-" .. i and created() == 1, s.label)
    local w = warned(logged)
    assert(#w == 1 and w[1]:find("projects: the label function", 1, true), table.concat(w, "; "))
  end
end)

test("shaping: a layout that fails or answers no windows falls back to one shell tab", function()
  for i, f in ipairs({
    function() error("boom") end,
    function() return nil end,
    function() return "x" end,
    function() return {} end,
  }) do
    again()
    P.setup{ layout = f, shell = "fish" }
    answers = { "my-app", { text = "layout-bad-" .. i }, 1 }
    local err, logged = ends(answers, I.worktree_run, {})
    P.setup{ layout = false, shell = false }
    assert(err == nil, err)
    local s = selected()
    assert(#s.windows == 1 and s.windows[1].window_label == "shell")
    local o = s.windows[1].layout.options
    assert(o.cwd == wt .. "/layout-bad-" .. i and o.shell == "fish")
    local w = warned(logged)
    assert(#w == 1 and w[1]:find("projects: the layout function", 1, true), table.concat(w, "; "))
    assert(not w[1]:find("0x", 1, true), w[1])
  end
end)

test("shaping: windows the server refuses fall back to one shell tab", function()
  P.setup{ layout = function() return { { window_label = "no layout" } } end }
  answers = { "my-app", { text = "layout-refused" }, 1 }
  local err, logged = ends(answers, I.worktree_run, {})
  P.setup{ layout = false }
  assert(err == nil, err)
  local s = selected()
  assert(#s.windows == 1 and s.windows[1].window_label == "shell" and s.cwd == wt .. "/layout-refused")
  local w = warned(logged)
  assert(#w == 1 and w[1]:find("refused the session with the layout function's windows: invalid_params", 1, true),
    table.concat(w, "; "))
end)

test("shaping: a plain folder has no branch", function()
  close_kept(plain)
  local seen = seen_by(nil, nil, function()
    answers = { "Add project…", { text = plain }, "Add plain" }
    I.switch_run({})
  end)
  assert(seen.label.project == "plain" and seen.label.branch == nil and seen.label.dir == plain)
  assert(seen.layout.branch == nil)
end)

test("shaping: a session on another host is shaped here", function()
  relays, local_execs = 0, 0
  local calls_in_relay = 0
  local seen = {}
  P.setup{
    label = function(t)
      if in_relay then calls_in_relay = calls_in_relay + 1 end
      seen.label = t
      return t.host .. ": " .. t.branch
    end,
    layout = function(t)
      if in_relay then calls_in_relay = calls_in_relay + 1 end
      seen.layout = t
      return { { window_label = "remote", layout = { options = { cwd = t.dir } } } }
    end,
  }
  answers = { "my-app", { text = "shape-remote" }, 1 }
  local err = ends(answers, I.worktree_run, { server = "studio" })
  P.setup{ label = false, layout = false }
  assert(err == nil, err)
  assert(calls_in_relay == 0 and local_execs == 0, "neither runs on the host")
  local s = assert(session("studio", remembered(wt .. "/shape-remote")), "made on studio")
  assert(s.label == "studio: shape-remote" and s.windows[1].window_label == "remote", s.label)
  assert(seen.label.host == "studio" and seen.label.dir == wt .. "/shape-remote")
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
  landed(I.backend.open_worktree{ project = plain })
  landed(I.backend.switch_here{ project = repo, name = "main" })
  local rows = I.project_rows()
  local _, at = ids(rows)
  assert(at[repo] == 1 and at[plain] == 2, "the last opened first, then the one before")
  -- The rest, never opened, by name.
  assert(#rows > 4, "more than two projects are listed")
  for i = 4, #rows - 1 do
    assert(rows[i - 1].title:lower() <= rows[i].title:lower(), "never opened, by name: " .. rows[i].title)
  end
  assert(rows[3].id == scratch and rows[#rows].id == ":add")

  -- A refusal, such as no name or a new name with no base, is no use.
  landed(I.backend.switch_here{ project = plain })
  assert(I.backend.switch_here{ project = repo, name = "" }.why ~= nil)
  assert(I.backend.switch_here{ project = repo, name = "mru-new" }.why == "no base was named")
  assert(top() == plain, "neither changes the order")

  -- A new worktree counts, and so does going back to it.
  landed(I.backend.open_worktree{ project = repo, name = "mru-wt", base = "main" })
  assert(top() == repo, "a new worktree")
  landed(I.backend.switch_here{ project = plain })
  landed(I.backend.open_worktree{ project = repo, name = "mru-wt" })
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

  -- Of two listed folders, one inside the other, the deeper one is first,
  -- also when the outer one is a repository.
  local docs = repo .. "/build/docs"
  os.execute("mkdir -p " .. sh(docs))
  I.backend.add{ path = plain .. "/sub" }
  I.backend.add{ path = docs }
  assert(order(plain .. "/sub")[1] == plain .. "/sub" and order(plain)[1] == plain)
  assert(order(docs)[1] == docs, "a listed folder inside a repository")
  assert(order(repo .. "/src")[1] == repo and order(wt .. "/mru-wt")[1] == repo, "the repository elsewhere")
  I.backend.forget{ project = plain .. "/sub" }
  I.backend.forget{ project = docs }

  -- A project listed through a symbolic link is found from the folder git
  -- names, whether or not the link has the folder's name.
  for _, name in ipairs({ "my-app", "alias" }) do
    local link = tmp .. "/link-" .. name .. "/" .. name
    os.execute("mkdir -p " .. sh(tmp .. "/link-" .. name) .. " && ln -s " .. sh(repo) .. " " .. sh(link))
    I.backend.forget{ project = repo }
    I.backend.add{ path = link }
    assert(order(repo)[1] == link, "the main checkout, by " .. name)
    assert(order(wt .. "/mru-wt")[1] == link, "a worktree, by " .. name)
    I.backend.forget{ project = link }
    I.backend.add{ path = repo }
  end
  I.load_state().recent = { plain, inner }

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
  I.switch_run({ session_id = mine.session_id, block_id = mine.block_id })
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

test("Remove Project hides a project a root finds, until it is added again", function()
  local root = tmp .. "/root"
  local found = root .. "/found"
  os.execute("mkdir -p " .. sh(found))
  git(found, "init", "-q", "-b", "main")
  local roots = I.config.roots
  P.setup{ roots = { root } }
  local function listed(rows) return select(2, ids(rows))[found] ~= nil end
  assert(listed(I.project_rows()) and listed(I.backend.saved().rows), "a root's project is listed in both")

  answers = { "found" }
  I.remove_run({})
  assert(asked[1].title == "Remove project")
  assert(not listed(I.project_rows()) and not listed(I.backend.saved().rows), "hidden from both")
  I.reset()
  assert(not listed(I.project_rows()), "the hide is read back from projects.json")

  I.backend.add{ path = found }
  assert(listed(I.project_rows()), "adding it again shows it")
  assert(#I.load_state().hidden == 0, "and takes it off the hidden list")
  for _, p in ipairs(I.load_state().projects) do assert(p ~= found, "a root's project gets no entry") end
  I.backend.forget{ project = found }
  assert(not listed(I.project_rows()), "an added project a root finds is hidden too")
  I.backend.add{ path = found }
  I.backend.forget{ project = found }
  I.backend.forget{ project = found }
  local hidden = 0
  for _, p in ipairs(I.load_state().hidden) do
    if p == found then hidden = hidden + 1 end
  end
  assert(hidden == 1, "hidden once: " .. hidden)

  -- Without the root, a project is added to the list and only taken off it.
  P.setup{ roots = roots }
  I.backend.add{ path = found }
  assert(#I.load_state().hidden == 0 and listed(I.backend.saved().rows), "no root, a list entry")
  I.backend.forget{ project = found }
  assert(#I.load_state().hidden == 0 and not listed(I.backend.saved().rows), "no root, nothing hidden")
end)

test("a project whose folder is missing is marked, put last, and removed only when chosen", function()
  local gone_a, gone_b = tmp .. "/gone/gone-a", tmp .. "/gone/gone-b"
  os.execute("mkdir -p " .. sh(gone_a) .. " " .. sh(gone_b))
  I.backend.add{ path = gone_b }
  I.backend.add{ path = gone_a }
  os.execute("rm -rf " .. sh(tmp .. "/gone"))

  -- checks counts the folder checks f runs, then every command it runs;
  -- fails makes the checks fail.
  local real_exec, fails = rex.exec, nil
  local function checks(f)
    local count, all = 0, 0
    rex.exec = function(argv, ...)
      all = all + 1
      if argv[1] == "sh" then
        count = count + 1
        if fails ~= nil then return fails() end
      end
      return real_exec(argv, ...)
    end
    local ok, err = pcall(f)
    rex.exec = real_exec
    assert(ok, err)
    return count, all
  end
  local function marked(rows)
    local list = {}
    for _, row in ipairs(rows) do
      if row.detail ~= nil then assert(row.detail == "missing"); list[#list + 1] = row.id end
    end
    return table.concat(list, " ")
  end
  local function without_gone(rows)
    local list = {}
    for _, row in ipairs(rows) do
      if row.id ~= gone_a and row.id ~= gone_b then list[#list + 1] = row.id end
    end
    return table.concat(list, " ")
  end

  -- A check that fails, or does not run, marks nothing.
  local plain_rows, plain_saved
  for _, answer in ipairs({
    function() return { ok = false, code = 1, stdout = gone_a .. "\0", stderr = "" } end,
    function() return nil, "sh: not found" end,
  }) do
    fails = answer
    assert(checks(function()
      plain_rows, plain_saved = I.project_rows(), I.backend.saved().rows
    end) == 2)
    assert(marked(plain_rows) == "" and marked(plain_saved) == "", "nothing marked")
  end
  fails = nil

  local rows, saved
  local picker_checks, picker_all = checks(function() rows = I.project_rows() end)
  local saved_checks, saved_all = checks(function() saved = I.backend.saved().rows end)
  assert(picker_checks == 1 and saved_checks == 1, "one check per listing")
  assert(rows[#rows].id == ":add", "Add project… stays last")
  -- order_in is the order of the two missing projects in rows.
  local function order_in(list)
    local at = select(2, ids(list))
    return at[gone_a] < at[gone_b] and gone_a .. " " .. gone_b or gone_b .. " " .. gone_a
  end
  assert(marked(rows) == order_in(plain_rows), "marked, in their order: " .. marked(rows))
  assert(rows[#rows - 2].detail and rows[#rows - 1].detail, "the missing ones come last")
  assert(without_gone(rows) == without_gone(plain_rows), "the others keep their order")
  assert(marked(saved) == order_in(plain_saved))
  assert(saved[#saved].detail and saved[#saved - 1].detail, "last in Remove Project too")
  assert(without_gone(saved) == without_gone(plain_saved))

  -- With no project added by hand, there is nothing to check.
  local s = I.load_state()
  local added = s.projects
  s.projects = {}
  local none, empty_picker = checks(function() I.project_rows() end)
  assert(none == 0, "no check")
  local none_saved, empty_saved = checks(function() I.backend.saved() end)
  assert(none_saved == 0, "no check")
  assert(picker_all == empty_picker + 1 and saved_all == empty_saved + 1,
    "exactly one extra command: " .. picker_all .. " vs " .. empty_picker .. ", " ..
    saved_all .. " vs " .. empty_saved)
  s.projects = added
  assert(checks(function() I.reset(); I.load_state() end) == 0, "no check on load")

  -- Keep, or Esc, ends the action, and the project stays.
  for _, answer in ipairs({ "Keep", false }) do
    again()
    answers = { "gone-a" }
    if answer then answers[2] = answer end
    I.switch_run({})
    assert(#asked == 2 and asked[2].title == "gone-a is missing", asked[#asked].title)
    assert(asked[2].items[1].title == "Keep" and asked[2].items[2].title == "Remove from list")
    assert(created() == 0 and #queued == 0, "no session")
    assert(marked(I.project_rows()):find(gone_a, 1, true), "still listed")
  end
  I.reset()
  assert(read(tmp .. "/state/projects.json"):find(gone_a, 1, true), "never removed by itself")

  -- A hidden project under a root that is no longer set goes with any Remove;
  -- one under a root still set stays, also when it is set with a slash.
  local kept_root, dropped_root = tmp .. "/kept-root", tmp .. "/dropped-root"
  for _, root in ipairs({ kept_root, dropped_root }) do
    os.execute("mkdir -p " .. sh(root .. "/found"))
    git(root .. "/found", "init", "-q", "-b", "main")
  end
  local roots = I.config.roots
  P.setup{ roots = { kept_root, dropped_root } }
  I.backend.forget{ project = kept_root .. "/found" }
  I.backend.forget{ project = dropped_root .. "/found" }
  assert(#I.load_state().hidden == 2, "both hidden")
  P.setup{ roots = { kept_root .. "/" } }

  -- Remove from list forgets it, everywhere, and opens no session.
  again()
  answers = { "gone-a", "Remove from list" }
  I.switch_run({})
  assert(#asked == 2 and created() == 0 and #queued == 0)
  assert(not select(2, ids(I.project_rows()))[gone_a] and not select(2, ids(I.backend.saved().rows))[gone_a])
  I.reset()
  for _, p in ipairs(I.load_state().projects) do assert(p ~= gone_a, "gone from projects.json") end
  local hidden = I.load_state().hidden
  assert(#hidden == 1 and hidden[1] == kept_root .. "/found", "only the set root's: " .. table.concat(hidden, " "))
  P.setup{ roots = roots }

  -- On another host the picker shows the host's check, run there.
  again()
  relays, local_execs = 0, 0
  local theirs = open_session("studio", "there", plain)
  theirs.attached = true
  answers = { "gone-b", "Keep" }
  I.switch_run({ server = "studio", session_id = theirs.session_id, block_id = theirs.block_id })
  assert(marked(asked[1].items) == gone_b and asked[2].title == "gone-b is missing")
  assert(local_execs == 0, "the check runs on the host: " .. local_execs)
  close("studio", theirs.session_id)

  -- Remove Project takes it off like any other, and the old hide goes too.
  again()
  answers = { "gone-b" }
  I.remove_run({})
  assert(marked(asked[1].items) == gone_b and asked[1].items[#asked[1].items].id == gone_b)
  assert(marked(I.project_rows()) == "" and #I.load_state().hidden == 0)
end)

test("git's progress lines are not the reason", function()
  assert(I.reason("Preparing worktree (checking out 'main')\nfatal: 'main' is already used") == "fatal: 'main' is already used")
  assert(I.reason("error: one\nfatal: two") == "error: one\nfatal: two")
  assert(I.reason("no marker here") == "no marker here")
end)

test("wt's progress lines and marks are not the reason", function()
  local stderr = "◎ Fetching PR #9...\n  T (#9)\n\27[31m✗\27[0m Failed to fetch branch x from origin\n" ..
    "   fatal: couldn't find remote ref refs/heads/x\n↳ To list branches, run wt list\n"
  assert(I.wt_reason(stderr) == "Failed to fetch branch x from origin. " ..
    "fatal: couldn't find remote ref refs/heads/x. To list branches, run wt list", I.wt_reason(stderr))
  assert(I.wt_reason("✗ Cannot remove worktree: a has uncommitted changes\n  ?? new.txt\n↳ Commit first\n") ==
    "Cannot remove worktree: a has uncommitted changes. Commit first")
  assert(I.wt_reason("error: unexpected argument '--x' found\n") == "error: unexpected argument '--x' found")
  assert(I.toml([[/a "b"\c]]) == [["/a \"b\"\\c"]], I.toml([[/a "b"\c]]))
end)

test("a state file from the version before keeps its projects", function()
  write(tmp .. "/state/projects.json", '{"projects":["/a/b"],"last":{"/a/b":"current"}}')
  I.reset()
  local s = I.load_state()
  assert(#s.projects == 1 and s.projects[1] == "/a/b" and next(s.sessions) == nil)
  assert(#s.recent == 0, "no order of use yet")
end)

test("a state file with bare session ids keeps its projects and recents, not the ids", function()
  write(tmp .. "/state/projects.json",
    '{"projects":["/a/b","/c"],"recent":["/c","/a/b"],"sessions":{"/a/b":"session:1","/c":{"session":"s"}}}')
  I.reset()
  local s = I.load_state()
  assert(#s.projects == 2 and s.projects[1] == "/a/b" and s.projects[2] == "/c")
  assert(#s.recent == 2 and s.recent[1] == "/c" and s.recent[2] == "/a/b")
  assert(next(s.sessions) == nil, "no record is kept")
end)

test("a record is saved and read back, and a session belongs to one checkout", function()
  local ab = tmp .. "/a/b"
  os.execute("mkdir -p " .. sh(ab .. "/wt") .. " " .. sh(ab .. "/other"))
  write(tmp .. "/state/projects.json", '{"projects":["/a/b"]}')
  I.reset()
  I.backend.keep{ dir = ab, session = "s1", created = true }
  I.backend.keep{ dir = ab .. "/wt", session = "s2", created = false }
  I.backend.keep{ dir = ab .. "/other", session = "s2", created = false }
  I.reset()
  local r = I.load_state().sessions
  assert(r[ab].session == "s1" and r[ab].created == true)
  assert(r[ab .. "/other"].session == "s2" and r[ab .. "/other"].created == false)
  assert(r[ab .. "/wt"] == nil, "the session moved to the other checkout")
end)

test("a record whose folder is gone is kept on load, and the load writes nothing", function()
  local ab = tmp .. "/a/b"
  os.execute("rm -rf " .. sh(ab .. "/other"))
  local file = tmp .. "/state/projects.json"
  local before = assert(read(file))
  I.reset()
  local r = I.load_state().sessions
  assert(r[ab].session == "s1" and r[ab .. "/other"].session == "s2")
  assert(read(file) == before, "the file is unchanged: " .. tostring(read(file)))
end)

test("a save stopped before its rename leaves the old file whole", function()
  local file = tmp .. "/state/projects.json"
  write(file, '{"projects":["/a/b","/c"],"recent":["/c"]}')
  I.reset()
  local before = read(file)
  I.load_state().projects[#I.load_state().projects + 1] = "/new"
  local logged, real_log, real_rename = {}, rex.log, os.rename
  rex.log = function(level, msg) logged[#logged + 1] = level .. " " .. msg end
  os.rename = function() return nil, "stopped" end
  local ok, err = pcall(I.save_state)
  os.rename, rex.log = real_rename, real_log
  assert(ok, err)
  assert(read(file) == before, "the old file is unchanged: " .. tostring(read(file)))
  assert(#logged == 1 and logged[1]:find("^warn .*stopped"), table.concat(logged, "\n"))
  assert(read(file .. ".tmp") == nil, "the temporary file is removed")
  I.reset()
  local s = I.load_state()
  assert(#s.projects == 2 and s.projects[2] == "/c" and #s.recent == 1 and s.recent[1] == "/c")
end)

test("without os.rename the save goes through mv", function()
  local file = tmp .. "/state/projects.json"
  I.reset()
  I.load_state().projects = { "/moved" }
  local real_rename, real_exec, moved = os.rename, rex.exec, false
  os.rename = nil
  rex.exec = function(argv, ...)
    if argv[1] == "mv" then moved = true end
    return real_exec(argv, ...)
  end
  local ok, err = pcall(I.save_state)
  os.rename, rex.exec = real_rename, real_exec
  assert(ok, err)
  assert(moved, "mv was run")
  assert(read(file .. ".tmp") == nil, "the temporary file is moved")
  I.reset()
  local s = I.load_state()
  assert(#s.projects == 1 and s.projects[1] == "/moved", read(file))
end)

test("a corrupt state file is an empty list", function()
  write(tmp .. "/state/projects.json", "{not json")
  I.reset()
  assert(#I.load_state().projects == 0)
end)

---------------------------------------------------------------------------
-- The login shell
---------------------------------------------------------------------------

local shells, login_bin = tmp .. "/shells", tmp .. "/login-bin"
os.execute("mkdir -p " .. sh(shells) .. " " .. sh(login_bin))
for _, name in ipairs({ "bash", "zsh", "fish" }) do
  write_file(shells .. "/" .. name, "#!/bin/sh\n" ..
    "printf '%s\\n' \"$*\" >> " .. sh(shells .. "/" .. name .. ".log") .. "\n" ..
    "echo 'Welcome back! PATH=/rc-noise'\n" ..
    "echo PATH=/stale\n" ..
    "echo PATH=" .. sh(login_bin .. ":" .. tmp .. "/bin:") .. "\"$PATH\"\n" ..
    "echo GH_TOKEN=login-secret\n" ..
    "echo UNLISTED=x\n")
end
write_file(shells .. "/broken", "#!/bin/sh\necho GH_TOKEN=login-secret\necho login-secret >&2\nexit 3\n")
write_file(login_bin .. "/only-login", "#!/bin/sh\necho found\n")
os.execute("chmod +x " .. sh(shells) .. "/* " .. sh(login_bin) .. "/*")

local function asked_lines(name)
  local f = io.open(shells .. "/" .. name .. ".log")
  if f == nil then return {} end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  os.remove(shells .. "/" .. name .. ".log")
  return lines
end

local function with_shell(shell, fn)
  local logged, real_log = {}, rex.log
  rex.log = function(level, msg) logged[#logged + 1] = "[" .. level .. "] " .. msg end
  test_shell = shell
  I.reset_login()
  local ok, err = pcall(fn)
  test_shell = nil
  rex.log = real_log
  prime_login()
  if not ok then error(err, 0) end
  for _, line in ipairs(logged) do
    assert(not line:find("login-secret", 1, true), "a value was logged: " .. line)
  end
  return logged
end

local function warnings(logged)
  local count = 0
  for _, line in ipairs(logged) do if line:find("^%[warn%]") then count = count + 1 end end
  return count
end

test("login shell: bash, zsh and fish find a command on the login PATH", function()
  for _, name in ipairs({ "bash", "zsh", "fish" }) do
    local logged = with_shell(shells .. "/" .. name, function()
      local opts = I.tool_opts(nil)
      assert(opts.env.PATH:find("^" .. login_bin:gsub("%p", "%%%0") .. ":"), "last PATH wins: " .. opts.env.PATH)
      assert(opts.env.GH_TOKEN == "login-secret" and opts.env.UNLISTED == nil)
      local r = rex.exec({ "only-login" }, opts)
      assert(r.ok and r.stdout == "found\n", name .. ": " .. tostring(r.stderr))
      local lines = asked_lines(name)
      assert(#lines == 1 and lines[1] == "-l -c env", name .. " was asked: " .. table.concat(lines, " | "))
    end)
    assert(warnings(logged) == 0, logged[1])
  end
end)

test("login shell: git and wt get the login variables, wt keeps its own", function()
  with_shell(shells .. "/zsh", function()
    I.backend.add{ path = repo }
    envs, timeouts = {}, {}
    answers = { "my-app", { text = "pr:8" } }
    I.worktree_run({ server = "studio" })
    local seen = {}
    local kept_off_network = false
    for _, e in ipairs(envs) do
      local tool = e.argv[1]
      assert(tool == "git" or tool == "wt", "only git and wt: " .. tool)
      seen[tool] = true
      assert(e.env.PATH:find(login_bin, 1, true) and e.env.GH_TOKEN == "login-secret", table.concat(e.argv, " "))
      assert(e.env.UNLISTED == nil)
      if tool == "wt" and e.relayed and e.env.GIT_ALLOW_PROTOCOL == "none" then kept_off_network = true end
    end
    assert(seen.git and seen.wt, "git and wt both ran")
    assert(kept_off_network, "wt's GIT_ALLOW_PROTOCOL survives in a relayed op")
    local lookups = 0
    for _, t in ipairs(timeouts) do
      if t.argv[1] == shells .. "/zsh" then
        lookups = lookups + 1
        assert(t.seconds == 5)
      end
    end
    assert(lookups == 1 and #asked_lines("zsh") == 1, "the shell was asked once")
  end)
  I.backend.forget{ project = repo }
end)

test("login shell: a variable only the server has still reaches the command", function()
  with_shell(shells .. "/bash", function()
    base_env.HTTPS_PROXY = "http://server-proxy"
    local r = rex.exec({ "sh", "-c", "echo $HTTPS_PROXY" }, I.tool_opts(nil))
    base_env.HTTPS_PROXY = nil
    assert(r.stdout == "http://server-proxy\n", r.stdout)
    asked_lines("bash")
  end)
end)

test("login shell: without $SHELL, commands use the server's environment", function()
  local logged = with_shell(nil, function()
    assert(I.tool_opts(nil) == nil)
    local opts = { timeout = 3 }
    assert(I.tool_opts(opts) == opts)
    I.tool_opts(nil)
  end)
  assert(warnings(logged) == 1 and logged[1]:find("$SHELL is not set", 1, true), logged[1])
end)

test("login shell: a failed lookup falls back and warns once", function()
  for _, shell in ipairs({ shells .. "/broken", shells .. "/missing" }) do
    local logged = with_shell(shell, function()
      for _ = 1, 3 do assert(I.tool_opts(nil) == nil) end
      local opts = { env = { GIT_ALLOW_PROTOCOL = "none" } }
      assert(I.tool_opts(opts) == opts)
    end)
    assert(warnings(logged) == 1, #logged .. " warnings")
    assert(logged[1]:find(shell, 1, true) and logged[1]:find("exited with status", 1, true), logged[1])
  end
end)

test("login shell: a slow lookup is stopped after 5 seconds", function()
  local logged = with_shell(shells .. "/fish", function()
    timeouts = {}
    stalls = function(argv) return argv[1] == shells .. "/fish" end
    local ok, opts = pcall(I.tool_opts, nil)
    stalls = nil
    assert(ok and opts == nil, "commands fall back")
    assert(#timeouts == 1 and timeouts[1].seconds == 5)
    local a = timeouts[1].argv
    assert(a[2] == "-l" and a[3] == "-c" and a[4] == "env" and #a == 4)
  end)
  assert(warnings(logged) == 1 and logged[1]:find("over 5 seconds", 1, true), logged[1])
end)

---------------------------------------------------------------------------
-- setup's checks
---------------------------------------------------------------------------

-- settings is a copy of the settings setup can change, the key bindings and
-- the loaded state.
local function settings()
  local copy = {}
  for k, v in pairs(I.config) do copy[k] = v end
  copy.bindings = bound("alt+cmd+n") .. "|" .. bound("ctrl+alt+cmd+n")
  copy.state = I.load_state()
  return copy
end
local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false, k end end
  for k, v in pairs(b) do if a[k] ~= v then return false, k end end
  return true
end

test("setup's checks: an unknown option is named and changes nothing", function()
  local before = settings()
  local _, logged = ends({}, function() P.setup{ keyy = "x" } end)
  local w = warned(logged)
  assert(#w == 1 and w[1] == "warn projects: setup has no option keyy", w[1])
  assert(same(before, settings()))
end)

test("setup's checks: a value of the wrong kind is named and keeps the previous one", function()
  local bad = {
    { "key", 3, "3" }, { "worktree_key", true, "true" }, { "base", 1, "1" },
    { "shell", {}, "a table" }, { "worktrees", false, "false" },
    { "roots", "~/src", '"~/src"' }, { "roots", { "a", 3 }, "a table" },
    { "roots", { "a", x = "b" }, "a table" },
    { "state_file", 5, "5" }, { "project_order", "sideways", '"sideways"' },
    { "branch_order", 1, "1" }, { "label", "x", '"x"' }, { "layout", 3, "3" },
  }
  for _, case in ipairs(bad) do
    local name, value, word = case[1], case[2], case[3]
    local before = settings()
    local err, logged = ends({}, function() return P.setup{ [name] = value } end)
    assert(err == nil, err)
    local w = warned(logged)
    assert(#w == 1, name .. ": " .. #w .. " warnings")
    assert(w[1]:find("^warn projects: " .. name .. " must be ") and w[1]:sub(-#word - 6) == ", not " .. word, w[1])
    assert(not w[1]:find("0x", 1, true), w[1])
    local ok, changed = same(before, settings())
    assert(ok, name .. " changed " .. tostring(changed))
  end
end)

test("setup's checks: false unsets the settings that allow it, without a warning", function()
  local _, logged = ends({}, function()
    P.setup{ base = "develop", shell = "fish", label = function() end, layout = function() end }
    P.setup{ key = false, worktree_key = false, base = false, shell = false, label = false, layout = false }
  end)
  assert(#warned(logged) == 0, logged[1])
  assert(bound("alt+cmd+n") == "" and bound("ctrl+alt+cmd+n") == "", "both keys removed")
  for _, name in ipairs({ "key", "worktree_key", "base", "shell", "label", "layout" }) do
    assert(not I.config[name], name)
  end
  P.setup{ key = "alt+cmd+n", worktree_key = "ctrl+alt+cmd+n" }
  assert(bound("alt+cmd+n") == "switch_project_branch" and bound("ctrl+alt+cmd+n") == "open_project_worktree")
end)

test("setup's checks: the rest of a call applies", function()
  local shell = I.config.shell
  local _, logged = ends({}, function() P.setup{ shell = 42, base = "develop", nope = 1 } end)
  local w = warned(logged)
  assert(#w == 2, #w .. " warnings")
  table.sort(w)
  assert(w[1] == "warn projects: setup has no option nope", w[1])
  assert(w[2] == "warn projects: shell must be a string or false, not 42", w[2])
  assert(I.config.base == "develop" and I.config.shell == shell)
  P.setup{ base = false }
end)

test("setup's checks: a list of strings, or none, is a good roots", function()
  local roots = I.config.roots
  local _, logged = ends({}, function()
    P.setup{ roots = { tmp .. "/a", tmp .. "/b" } }
    assert(#I.config.roots == 2)
    P.setup{ roots = {} }
  end)
  assert(#warned(logged) == 0, logged[1])
  assert(#I.config.roots == 0)
  P.setup{ roots = roots }
end)

test("setup's checks: a new state_file is read afresh", function()
  local file = I.config.state_file
  local before = I.load_state()
  table.insert(before.projects, tmp .. "/marker")
  I.save_state()
  P.setup{ state_file = tmp .. "/other-projects.json" }
  local fresh = I.load_state()
  P.setup{ state_file = file }
  assert(fresh ~= before and #fresh.projects == 0 and next(fresh.sessions) == nil)
  local back = I.load_state()
  assert(back ~= fresh and back.projects[#back.projects] == tmp .. "/marker", "the first file is read again")
  table.remove(back.projects)
  I.save_state()
end)

test("setup's checks: a value or name with a newline is warned about on one line", function()
  local _, logged = ends({}, function() P.setup{ shell = { }, ["a\nb"] = 1, project_order = "up\ndown" } end)
  local w = warned(logged)
  assert(#w == 3, #w .. " warnings")
  for _, line in ipairs(w) do assert(not line:find("\n"), line) end
end)

test("setup's checks: setup takes a table, or nothing", function()
  local before = settings()
  local result
  local _, logged = ends({}, function() result = P.setup("x") end)
  local w = warned(logged)
  assert(result == P and #w == 1 and w[1] == 'warn projects: setup takes a table, not "x"', w[1])
  assert(same(before, settings()))
  _, logged = ends({}, function() result = P.setup() end)
  assert(result == P and #logged == 0)
  assert(same(before, settings()))
end)

test("no wt call passed --yes or -y", function()
  assert(#wt_argv > 100, "wt ran: " .. #wt_argv)
  for _, argv in ipairs(wt_argv) do
    assert(not holds(argv, "--yes") and not holds(argv, "-y"), table.concat(argv, " "))
  end
end)

tidy()
print(n .. " passed")
