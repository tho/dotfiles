-- rex-projects: pick a project, then a branch, and land in its session.
-- README.md says what each action and setting does; this says how the code
-- is put together.
--
-- Pickers and backend. The actions (see "The actions") run in the app's own
-- server, the one on the Mac, because the app lists and binds only that
-- server's actions. They do the asking: rex.ui.pick lists, and the session
-- calls. Everything that reads folders, runs git, wt or gh, or touches the
-- saved state is an op of the backend table, run where the projects are.
-- Ops never ask the person anything. Each answers a table of plain values,
-- or { why = message } when the request cannot be done, carrying the
-- tool's own words where git, wt or gh refused, and the action fails with
-- it (fail).
--
-- The relay. connect picks where ops run: here, as a plain call, or, for a
-- focused session on a remote host, through client.action to that server's
-- projects_backend action, which needs this file in that host's init.lua.
-- The answer travels as JSON, and the caller waits 10 seconds at most, so a
-- relayed op runs network commands under net_limit and stops them in time.
-- Session calls (session.create and the rest) go to the same server.
--
-- The session store (see "State"). projects.json holds the project list,
-- the order of last use, and a record { session, created } for each
-- checkout's folder. The backend owns it: landing reads the record and says
-- whether the action's own session may be adopted, keep stores the session
-- an action landed in, and cleanup and forget_record hand a forgotten
-- record back. session_for, in the actions, finds, adopts or creates the
-- session; close_session is the one close path, and it closes only a
-- session rex-projects created; close_project_session, for wt's post-remove
-- hook, takes it on its own host. Records are hints that git, wt or a person
-- can outdate at any time, so each is checked before use.
--
-- git, wt and gh run through rex.exec with argument lists, with PATH and a
-- few other variables from the login shell (login_env). The script is
-- written for Lua 5.1, as Rex embeds it; test/run.lua runs it against a
-- stand-in for Rex, and test/host.lua against a real server.

local M = {}

-- Servers before control API revision 17 have no rex.ui. Do nothing there
-- instead of failing the whole init.lua.
local has_ui, ui = pcall(function() return rex.ui end)
if not has_ui or ui == nil then
  return M
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- The settings. A call to M.setup replaces the ones it names.
local config = {
  key = "alt+cmd+n", -- runs Switch Branch in Project…
  worktree_key = "ctrl+alt+cmd+n", -- runs Open Worktree in Project…
  base = nil, -- what a new branch starts from unless another is chosen; nil
  -- means the default branch that wt finds
  shell = nil, -- nil means the account's default shell
  worktrees = nil, -- nil means <home>/.rex/worktrees
  roots = {},
  project_order = "recent", -- the project picker's order: "recent" or "name"
  branch_order = "recent", -- the branch lists' order: "recent" (newest commit) or "name"
  state_file = nil, -- nil means <config dir>/rex/projects.json
  label = nil, -- a function that answers a session's label; nil means rex-projects' own
  layout = nil, -- a function that answers a new session's windows; nil means one shell tab
}

-- The action that each key setting runs.
local key_actions = {
  key = "switch_project_branch",
  worktree_key = "open_project_worktree",
}

-- The binding made for each key setting, so that setup can remove it.
local bound_keys = {}

---------------------------------------------------------------------------
-- Platform
---------------------------------------------------------------------------

-- env returns an environment variable, or nil when it is unset or empty, or
-- when this script has no os library.
local function env(name)
  if os == nil or os.getenv == nil then return nil end
  local value = os.getenv(name)
  if value == nil or value == "" then return nil end
  return value
end

local home = env("HOME") or ""

-- trim removes blanks from both ends of s.
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- one_line is s trimmed, with each run of blanks and newlines as one space.
local function one_line(s)
  return (trim(tostring(s)):gsub("%s+", " "))
end

-- shown is a value as a warning shows it: a string quoted on one line, a
-- number or boolean as it is, anything else by its type.
local function shown(v)
  if type(v) == "string" then return (string.format("%q", v):gsub("\\\n", "\\n")) end
  if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
  return "a " .. type(v)
end

-- expand writes a leading ~ as the home folder and trims blanks and quotes
-- that a pasted path carries.
local function expand(path)
  path = trim(path)
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  if path == "~" then return home end
  if path:sub(1, 2) == "~/" then return home .. path:sub(2) end
  return path
end

-- short writes the home folder at the start of path as ~.
local function short(path)
  if home ~= "" and path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

-- basename returns the last component of a slash-separated path.
local function basename(path)
  return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

-- output runs a command and returns what it printed, or nil when it failed
-- or did not run. Its arguments are rex.exec's, passed on as they came.
local function output(...)
  local r = rex.exec(...)
  if r == nil or not r.ok then return nil end
  return r.stdout
end

-- decode reads text as a JSON object or list, or returns nil for anything
-- else.
local function decode(text)
  local ok, decoded = pcall(rex.json.decode, text)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

-- or_status returns message, the reason a tool gave for failing, or its exit
-- status when it gave none.
local function or_status(message, tool, r)
  if message ~= "" then return message end
  return tool .. " exited with status " .. tostring(r.code)
end

-- worktrees_dir is the folder that new worktrees are made in, as
-- <dir>/<repository>/<branch>; see worktree_path.
local function worktrees_dir()
  if config.worktrees then return expand(config.worktrees) end
  return home .. "/.rex/worktrees"
end

-- real returns dir as the system spells it, with every symbolic link
-- followed, or dir itself when that cannot be found out.
local function real(dir)
  local out = output({ "pwd", "-P" }, { cwd = dir })
  if out == nil then return dir end
  out = trim(out)
  return out ~= "" and out or dir
end

-- spelled returns path as the system spells it, like real, also when the
-- folder is gone: its nearest existing parent is spelled, and the rest kept.
local function spelled(path)
  local out = output({ "pwd", "-P" }, { cwd = path })
  if out ~= nil and trim(out) ~= "" then return trim(out) end
  local parent, name = path:match("^(.+)/([^/]+)$")
  if parent == nil then return path end
  return spelled(parent) .. "/" .. name
end

-- is_folder says whether path is a folder on this machine.
local function is_folder(path)
  return output({ "test", "-d", path }) ~= nil
end

-- missing returns the set of paths that are no folder on this machine,
-- checked with one command, or an empty set when that command fails.
local function missing(paths)
  local gone = {}
  if #paths == 0 then return gone end
  local out = output({ "sh", "-c", 'for p; do [ -d "$p" ] || printf "%s\\0" "$p"; done', "sh",
    unpack(paths) })
  if out == nil then return gone end
  for p in out:gmatch("[^%z]+") do gone[p] = true end
  return gone
end

---------------------------------------------------------------------------
-- State: the project list and each checkout's session
---------------------------------------------------------------------------

-- state is { projects = { path, ... }, sessions = { [folder] = record },
-- recent = { path, ... }, hidden = { path, ... } }. recent holds the projects
-- that were opened, the last one first. hidden holds the projects a root
-- finds that Remove Project took off the list, until added again or its
-- root is no longer set; a path in projects is shown whatever hidden says.
--
-- sessions holds a record { session = id, created = boolean } for a
-- checkout, by its folder: a project's own folder, or the folder of one of
-- its worktrees. The rules:
--   - a checkout has at most one record, and a session belongs to at most
--     one checkout: keep drops any other record of the session it stores;
--   - created says rex-projects made the session. Only such a session is
--     ever closed; an adopted one is forgotten and stays open;
--   - a record is a hint: git, wt or a person may remove the checkout or
--     close the session at any time. Before a record that may stop an
--     adoption is used, the backend checks its folder (record_at); one whose
--     folder is gone is dropped, as if there were none. The close path checks
--     only the session (session_exists): Clean Up of a worktree whose folder
--     was deleted by hand still closes the session rex-projects made for it.
--     The record of the checkout an action lands in is kept as it is: its
--     folder is there by then, and a worktree made again at the same path
--     keeps its session;
--   - a record whose folder is gone is kept until an action reaches it
--     (record_at, forget_record, keep), so a hook can still close its
--     session after a restart.
-- A value in any other shape, such as the bare id an older version kept, is
-- skipped on load and leaves the file at the next save.
local state = nil

-- state_path returns where the state is kept, or nil when there is nowhere.
local function state_path()
  if config.state_file then return expand(config.state_file) end
  local base = env("XDG_CONFIG_HOME") or (home ~= "" and (home .. "/.config") or nil)
  if base == nil then return nil end
  return base .. "/rex/projects.json"
end

-- warned_memory_only keeps the log to one warning about a missing io library.
local warned_memory_only = false

-- strings returns the strings of a decoded JSON list, in order, and an empty
-- list for anything that is not a list.
local function strings(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, v in ipairs(list) do
    if type(v) == "string" then out[#out + 1] = v end
  end
  return out
end

-- load_state reads the state once and returns it. A missing or unreadable
-- file is an empty state: a corrupt list must never stop a session starting.
local function load_state()
  if state ~= nil then return state end
  state = { projects = {}, sessions = {}, recent = {}, hidden = {} }
  local path = state_path()
  if io == nil or io.open == nil or path == nil then return state end
  local file = io.open(path, "r")
  if file == nil then return state end
  local text = file:read("*a")
  file:close()
  local decoded = decode(text)
  if decoded ~= nil then
    -- Read each member by hand: another version of this file may hold more.
    state.projects = strings(decoded.projects)
    state.recent = strings(decoded.recent)
    state.hidden = strings(decoded.hidden)
    if type(decoded.sessions) == "table" then
      for k, v in pairs(decoded.sessions) do
        if type(k) == "string" and type(v) == "table" and type(v.session) == "string"
            and type(v.created) == "boolean" then
          state.sessions[k] = { session = v.session, created = v.created }
        end
      end
    end
  end
  return state
end

-- replace moves tmp over path, with os.rename when the runtime has it.
local function replace(tmp, path)
  if os ~= nil and os.rename ~= nil then return os.rename(tmp, path) end
  local r, err = rex.exec({ "mv", "-f", tmp, path })
  if r == nil then return nil, err end
  if not r.ok then return nil, trim(r.stderr) end
  return true
end

local function remove(file)
  if os ~= nil and os.remove ~= nil then os.remove(file) else rex.exec({ "rm", "-f", file }) end
end

-- save_state writes the state. It returns nothing and never raises: failing
-- to remember is not worth stopping a session for. It writes a temporary file
-- and renames it over the old one, so a save cut short leaves the old file.
local function save_state()
  local path = state_path()
  if io == nil or io.open == nil or path == nil then
    if not warned_memory_only then
      warned_memory_only = true
      rex.log("warn", "projects: no place to save the project list; it lasts until the server restarts")
    end
    return
  end
  local dir = path:match("^(.*)/[^/]+$")
  if dir then rex.exec({ "mkdir", "-p", dir }) end
  local tmp = path .. ".tmp"
  local file, err = io.open(tmp, "w")
  local ok = file ~= nil
  if ok then
    ok, err = file:write(rex.json.encode({ projects = state.projects, sessions = state.sessions,
      recent = state.recent, hidden = state.hidden }))
    local closed, close_err = file:close()
    if ok and not closed then ok, err = false, close_err end
    if ok then ok, err = replace(tmp, path) end
  end
  if not ok then
    rex.log("warn", "projects: cannot save " .. path .. ": " .. tostring(err))
    if file ~= nil then remove(tmp) end
  end
end

---------------------------------------------------------------------------
-- Git
---------------------------------------------------------------------------

-- reason returns git's message from its first "fatal:" or "error:" line on.
-- Before that line git says what it was doing ("Preparing worktree…"), which
-- is not why it stopped. A message with no such line comes back whole.
local function reason(message)
  local text = "\n" .. message
  local first = nil
  for _, mark in ipairs({ "\nfatal: ", "\nerror: " }) do
    local at = text:find(mark, 1, true)
    if at ~= nil and (first == nil or at < first) then first = at end
  end
  if first == nil then return message end
  return text:sub(first + 1)
end

-- A backend op that another server asked for has 10 seconds to answer, and
-- the caller gives up after that while the op carries on. So in such an op
-- the commands that use the network, git fetch and gh, together get
-- NET_SECONDS, and one that is not done by then is stopped and says so.
-- net_limit is set while such an op runs: by is the time they must end by,
-- or nil where this script has no clock.
local NET_SECONDS = 8
local net_limit = nil

-- net_timeout returns the seconds a network command may still take, or nil
-- when nothing limits it.
local function net_timeout()
  if net_limit == nil then return nil end
  -- Without a clock, two commands in a row must still fit.
  if net_limit.by == nil then return NET_SECONDS / 2 end
  return math.max(1, net_limit.by - os.time())
end

-- timed_out is what a command stopped by net_timeout answers.
local function timed_out(what)
  return what .. " did not finish in the time a step on another host has (" ..
    NET_SECONDS .. " seconds), and was stopped"
end

local LOGIN_VARS = {
  "PATH", "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
  "GH_HOST", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "SSH_AUTH_SOCK",
}
local LOGIN_SECONDS = 5
local login_cache = nil

-- The Rex server's PATH can lack Homebrew on a Mac, so git, wt and gh are
-- found through the login shell.
local function login_env()
  if login_cache ~= nil then return login_cache end
  login_cache = false
  local shell = env("SHELL")
  if shell == nil then
    rex.log("warn", "projects: $SHELL is not set; git, wt and gh use the server's environment")
    return login_cache
  end
  local r, err = rex.exec({ shell, "-l", "-c", "env" }, { timeout = LOGIN_SECONDS })
  local problem = nil
  if r == nil then
    problem = shell .. " -l did not run (" .. tostring(err or "no reason given") .. ")"
  elseif r.timed_out then
    problem = shell .. " -l took over " .. LOGIN_SECONDS .. " seconds"
  elseif not r.ok then
    problem = shell .. " -l exited with status " .. tostring(r.code)
  end
  if problem ~= nil then
    rex.log("warn", "projects: cannot read the login shell's environment: " .. problem ..
      "; git, wt and gh use the server's environment")
    return login_cache
  end
  local wanted = {}
  for _, name in ipairs(LOGIN_VARS) do wanted[name] = true end
  local found = {}
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local name, value = line:match("^([%w_]+)=(.*)$")
    if name ~= nil and wanted[name] and value ~= "" then found[name] = value end
  end
  if next(found) ~= nil then login_cache = found end
  return login_cache
end

local function tool_opts(opts)
  local login = login_env()
  if not login then return opts end
  local merged = {}
  for k, v in pairs(opts or {}) do merged[k] = v end
  merged.env = {}
  for k, v in pairs(login) do merged.env[k] = v end
  for k, v in pairs(opts and opts.env or {}) do merged.env[k] = v end
  return merged
end

-- git_in runs git in dir, for at most timeout seconds when one is given,
-- and returns what it printed, or nil and git's message.
-- Arguments go as a list, never through a shell, so no quoting is needed.
local function git_in(timeout, dir, ...)
  local r, err = rex.exec({ "git", "-C", dir, ... }, tool_opts(timeout and { timeout = timeout } or nil))
  if r == nil then return nil, tostring(err or "git did not run") end
  if r.timed_out then return nil, timed_out("git " .. tostring((...))) end
  if not r.ok then return nil, reason(or_status(trim(r.stderr), "git", r)) end
  return r.stdout
end

-- git runs a git command that stays on this machine.
local function git(dir, ...) return git_in(nil, dir, ...) end

-- git_text returns what such a command printed, trimmed, or "" when it failed.
local function git_text(dir, ...) return trim(git(dir, ...) or "") end

-- git_net runs one that uses the network, such as fetch.
local function git_net(dir, ...) return git_in(net_timeout(), dir, ...) end

---------------------------------------------------------------------------
-- Worktrunk
---------------------------------------------------------------------------

-- wt_reason returns why wt stopped, from what it wrote to stderr, on one
-- line: its error, marked ✗, git's own error under it, and its hints,
-- marked ↳. The progress lines before the error are not the reason. A
-- message with no such mark, such as a usage error, comes back whole.
local function wt_reason(stderr)
  -- wt colours nothing when stderr is no terminal, unless told to.
  local text = stderr:gsub("\27%[[%d;]*%a", "")
  text = text:gsub("\r", "")
  local parts, started = {}, false
  for line in text:gmatch("[^\n]+") do
    local err, hint = line:match("^✗%s*(.-)%s*$"), line:match("^↳%s*(.-)%s*$")
    if err ~= nil then
      started = true
      parts[#parts + 1] = err
    elseif started and hint ~= nil then
      parts[#parts + 1] = hint
    elseif started and (line:find("fatal: ", 1, true) or line:find("error: ", 1, true)) then
      parts[#parts + 1] = trim(line)
    end
  end
  if #parts == 0 then return trim(text) end
  local out = parts[1]
  for i = 2, #parts do
    if not out:find("[.:;!?]$") then out = out .. "." end
    out = out .. " " .. parts[i]
  end
  return out
end

-- wt_in runs wt in project and returns rex.exec's result, or nil and why,
-- and true as well when the command was stopped for taking too long.
--
-- In an op that another server asked for, see net_limit, a command that
-- uses the network (network true) gets what is left of NET_SECONDS. Every
-- other one is kept off the network: GIT_ALLOW_PROTOCOL=none stops each git
-- command wt runs from reaching a remote. That matters for the default
-- branch, which wt asks the remote for, for up to 10 seconds, when neither
-- its own record nor <remote>/HEAD names it. Kept off the network, wt finds
-- it among the local branches instead and records that, so later commands
-- read it from the record.
local function wt_in(project, network, ...)
  local opts = nil
  if net_limit ~= nil then
    if network then
      opts = { timeout = net_timeout() }
    else
      opts = { env = { GIT_ALLOW_PROTOCOL = "none" } }
    end
  end
  local r, err = rex.exec({ "wt", "-C", project, ... }, tool_opts(opts))
  if r == nil or r.code == 127 then
    return nil, "wt did not run (" .. tostring(err or trim(r and r.stderr or "")) ..
      "). The Projects actions need worktrunk (https://worktrunk.dev) on PATH (the login shell's)."
  end
  if r.timed_out then return nil, timed_out("wt " .. tostring((...))), true end
  return r
end

-- wt_hooked runs a wt command whose hooks run, as wt_in does. Hooks run as
-- in a terminal, network and all, so in an op another server asked for the
-- command gets the network's time limit. wt finds the default branch off
-- the network first, as Review Pull Request does.
local function wt_hooked(project, ...)
  if net_limit ~= nil then wt_in(project, false, "config", "state", "default-branch") end
  return wt_in(project, true, ...)
end

-- wt_why returns why wt failed, from rex.exec's result r. A hook that needs
-- approval, which wt cannot ask for without a terminal, is named with its
-- commands, and with what to run in a terminal to approve them.
local function wt_why(project, r)
  local text = (r.stderr or ""):gsub("\27%[[%d;]*%a", "")
  text = text:gsub("\r", "")
  if not text:find("Cannot prompt for approval", 1, true) then
    return or_status(wt_reason(r.stderr or ""), "wt", r)
  end
  local parts, started = {}, false
  for line in text:gmatch("[^\n]+") do
    local asks = line:match("^▲%s*(.-)%s*$")
    if asks ~= nil then
      started = true
      parts[#parts + 1] = asks
    elseif started and line:find("^✗") then
      break
    elseif started then
      local command = trim(line:gsub("^○%s*", ""))
      if command ~= "" then parts[#parts + 1] = command end
    end
  end
  local asked = table.concat(parts, " ")
  if asked ~= "" and not asked:find("[.:;!?]$") then asked = asked .. "." end
  if asked ~= "" then asked = asked .. " " end
  return asked .. "wt cannot ask for approval without a terminal: run wt config approvals add " ..
    "in a terminal in " .. short(project) .. ", then try again"
end

-- wt runs wt and returns its JSON answer, decoded, or nil and wt's message,
-- and true as well when it was stopped for taking too long. how is "hooks"
-- for a command whose hooks run (see wt_hooked), else whether it uses the
-- network (see wt_in).
local function wt(project, how, ...)
  local r, err, stopped
  if how == "hooks" then
    r, err, stopped = wt_hooked(project, ...)
  else
    r, err, stopped = wt_in(project, how, ...)
  end
  if r == nil then return nil, err, stopped end
  if not r.ok then return nil, wt_why(project, r) end
  local decoded = decode(r.stdout)
  if decoded == nil then return nil, "wt did not answer with JSON: " .. trim(r.stdout) end
  return decoded
end

-- toml writes s as a TOML string.
local function toml(s)
  local escaped = s:gsub('[\\"]', "\\%0")
  return '"' .. escaped .. '"'
end

-- worktree_path is the --config-set that puts a new worktree in
-- <worktrees>/<repository>/<branch>, a slash in the branch written as a
-- dash. It goes with every wt switch, over what wt's own config says.
local function worktree_path()
  return "worktree-path=" .. toml(worktrees_dir() .. "/{{ repo }}/{{ branch | sanitize }}")
end

-- is_repo_root says whether dir is the top folder of a repository. It asks for
-- the way up to the top, which is empty at the top, instead of comparing paths:
-- git spells a symlinked folder (/tmp, a linked ~/src) its own way.
local function is_repo_root(dir)
  local out = git(dir, "rev-parse", "--show-cdup")
  return out ~= nil and trim(out) == ""
end

-- toplevel returns the top folder of the checkout that holds dir, as git
-- spells it, or nil when dir is in no checkout.
local function toplevel(dir)
  local out = git_text(dir, "rev-parse", "--show-toplevel")
  return out ~= "" and out or nil
end

-- current_branch returns the branch checked out in dir, or nil when HEAD is
-- detached.
local function current_branch(dir)
  local out = git_text(dir, "symbolic-ref", "--short", "-q", "HEAD")
  return out ~= "" and out or nil
end

-- has_ref says whether the repository of project has the ref, which is
-- written in full, such as refs/heads/main. Only that exact name counts:
-- rev-parse would also take a revision such as main~1 for a branch.
local function has_ref(project, ref)
  return git(project, "show-ref", "--verify", "--quiet", ref) ~= nil
end

-- worktrees lists a project's checkouts, main one first, as
-- { path = ..., branch = ... or nil, prunable = boolean }. It returns nil and
-- git's message for a folder that is not a repository, or one git cannot
-- read.
local function worktrees(project)
  local out, err = git(project, "worktree", "list", "--porcelain")
  if out == nil then return nil, err end
  local list = {}
  -- Each checkout is a paragraph of lines. Appending a blank line makes the
  -- last one end like the others.
  -- Take gsub's first result into a local before using it. A gsub call inside
  -- a ".." expression, with :gmatch called on the result, makes gopher-lua
  -- (the Lua in Rex) panic with a nil dereference.
  local text = out:gsub("\r", "")
  text = text .. "\n"
  for entry in text:gmatch("(.-)\n\n") do
    local path = entry:match("^worktree ([^\n]+)")
    if path then
      list[#list + 1] = {
        path = path,
        branch = entry:match("\nbranch refs/heads/([^\n]+)"),
        prunable = entry:find("\nprunable", 1, true) ~= nil,
      }
    end
  end
  return list
end

-- branch_sort returns how for-each-ref sorts branches for branch_order.
local function branch_sort()
  if config.branch_order == "name" then return "--sort=refname" end
  return "--sort=-committerdate"
end

-- local_branches returns the names of the branches in branch_order.
local function local_branches(project)
  -- lstrip=2 gives the name as it is. short would write a branch that shares
  -- its name with a remote branch as heads/<name>.
  local out = git(project, "for-each-ref", branch_sort(),
    "--format=%(refname:lstrip=2)", "refs/heads")
  local names = {}
  if out == nil then return names end
  for line in out:gmatch("[^\r\n]+") do names[#names + 1] = line end
  return names
end

-- remote_branches lists the branches of every remote in branch_order,
-- as { name = "origin/x", branch = "x" }: what git calls the branch, and
-- what a local branch made from it is called.
local function remote_branches(project)
  local list = {}
  local remotes = {}
  local out = git(project, "remote")
  if out == nil then return list end
  for line in out:gmatch("[^\r\n]+") do remotes[#remotes + 1] = line end
  -- A remote's name may hold a slash. The longest name that fits wins, so
  -- that a remote "team/ci" is not read as the remote "team".
  table.sort(remotes, function(a, b) return #a > #b end)
  out = git(project, "for-each-ref", branch_sort(),
    "--format=%(refname:lstrip=2)", "refs/remotes")
  if out == nil then return list end
  for name in out:gmatch("[^\r\n]+") do
    for _, remote in ipairs(remotes) do
      if name:sub(1, #remote + 1) == remote .. "/" then
        local branch = name:sub(#remote + 2)
        -- <remote>/HEAD says which branch is the remote's main one; it is
        -- not a branch.
        if branch ~= "HEAD" then list[#list + 1] = { name = name, branch = branch } end
        break
      end
    end
  end
  return list
end

-- branch_name returns text as a branch name: no branch name holds a space,
-- so a typed one means a dash.
local function branch_name(text)
  local name = trim(text or ""):gsub("%s+", "-")
  return name
end

-- remote_branch returns the remote branch of project that git calls name,
-- such as origin/x, as remote_branches lists it, or nil.
local function remote_branch(project, name)
  for _, r in ipairs(remote_branches(project)) do
    if r.name == name then return r end
  end
  return nil
end

-- pr_number reads a pull request from what was typed or chosen: 123, #123,
-- or a link to it or to a page of it, such as /pull/123/files.
local function pr_number(text)
  text = trim(tostring(text or ""))
  return tonumber(text:match("^#?(%d+)$") or text:match("/pull/(%d+)$")
    or text:match("/pull/(%d+)[/?#]"))
end

-- typed_name says what text, a branch name typed or picked in project, whose
-- checkouts are c, is. It answers { kind, name }, name as git will get it,
-- with kind one of
--   current   the main checkout's branch, or HEAD when that is detached
--   local     a local branch
--   remote    a remote branch such as origin/x, with branch = "x"
--   shortcut  wt's ^ (the default branch) or - (wt's previous branch)
--   pr        a pull request, pr:N or a link to one, with pr = what Review
--             takes for it
--   new       a name git takes for a new branch
-- or nil and why it names no branch. A bare number is a branch name.
local function typed_name(project, c, text)
  local name = branch_name(text)
  if name == "" then return nil, "no branch was named" end
  if name == "^" or name == "-" then return { kind = "shortcut", name = name } end
  local n = name:match("^pr:(%d+)$")
  if n ~= nil then return { kind = "pr", name = name, pr = "#" .. n } end
  if name:find("^https?://") and pr_number(name) ~= nil then
    return { kind = "pr", name = name, pr = name }
  end
  if name == (c.current or "HEAD") then return { kind = "current", name = name } end
  if has_ref(project, "refs/heads/" .. name) then return { kind = "local", name = name } end
  local remote = remote_branch(project, name)
  if remote ~= nil then return { kind = "remote", name = name, branch = remote.branch } end
  local out, err = git(project, "check-ref-format", "--branch", name)
  if out == nil then return nil, err end
  -- git expands a name such as @{-1} to the branch it stands for, and
  -- reads @ as HEAD.
  local read = trim(out)
  if read == "@" then read = "HEAD" end
  if read ~= name then return nil, name .. " is not a branch name: git reads it as " .. read end
  return { kind = "new", name = name }
end

---------------------------------------------------------------------------
-- Projects
---------------------------------------------------------------------------

-- repos_in lists the repositories directly inside dir, as paths.
-- A repository has a .git entry: a folder, or a file in a worktree.
-- -print0 ends each path with NUL, the one byte a path cannot hold.
local function repos_in(dir)
  local found = {}
  local out = output({ "find", dir, "-mindepth", "2", "-maxdepth", "2", "-name", ".git", "-print0" })
  if out == nil then return found end
  for hit in out:gmatch("[^%z]+") do
    local path = hit:match("^(.*)/%.git$")
    if path then found[#found + 1] = path end
  end
  return found
end

-- scan lists the repositories directly under each folder in config.roots,
-- as paths. Only folders are searched, one level down, so it stays quick.
local function scan()
  local found = {}
  for _, root in ipairs(config.roots) do
    for _, path in ipairs(repos_in(expand(root))) do found[#found + 1] = path end
  end
  return found
end

-- The ids of the rows that are not a folder. They travel as JSON between
-- servers, so they hold no NUL byte; a colon keeps them apart from any real
-- path, which starts with "/".
local ADD_PROJECT = ":add"
local ADD_HERE = ":here"
local UP = ":up"

-- RECENT_LIMIT is how many projects the recent list keeps.
local RECENT_LIMIT = 100

-- mark_used puts project first on the recent list.
local function mark_used(project)
  local s = load_state()
  local list = { project }
  for _, p in ipairs(s.recent) do
    if p ~= project and #list < RECENT_LIMIT then list[#list + 1] = p end
  end
  s.recent = list
  save_state()
end

-- project_row returns the picker row of the project at path, marked when
-- its folder is missing.
local function project_row(path, gone)
  return { id = path, title = basename(path), subtitle = short(path), icon = "folder",
    detail = gone and "missing" or nil }
end

-- rows_of returns the rows of paths in their order, those in gone last.
local function rows_of(paths, gone)
  local rows, last = {}, {}
  for _, p in ipairs(paths) do
    if gone[p] then last[#last + 1] = project_row(p, true) else rows[#rows + 1] = project_row(p) end
  end
  for _, row in ipairs(last) do rows[#rows + 1] = row end
  return rows
end

-- containing returns the project of paths that holds the folder cwd, or nil.
-- A worktree belongs to the project of its main checkout, which is the first
-- checkout git lists. A plain folder goes by its path, and the deepest
-- project that holds cwd wins.
local function containing(paths, cwd)
  if cwd == nil or cwd == "" then return nil end
  local trees = worktrees(cwd)
  local main = trees and trees[1] and trees[1].path or nil
  -- The terminal and the list may spell a folder through a symbolic link.
  local real_cwd = real(cwd)
  local repo, best = nil, nil
  for _, p in ipairs(paths) do
    if main ~= nil and repo == nil and p == main then repo = p end
    local function holds(dir) return dir == p or dir:sub(1, #p + 1) == p .. "/" end
    if (holds(cwd) or holds(real_cwd)) and (best == nil or #p > #best) then best = p end
  end
  -- A project listed through a link is not spelled as git spells the main
  -- checkout. Asking how each is really spelled costs a command a project,
  -- so it is done only when no project is the main checkout by name.
  if main ~= nil and repo == nil then
    for _, p in ipairs(paths) do
      if real(p) == main then repo = p; break end
    end
  end
  if repo == nil then return best end
  -- A listed folder inside the checkout that holds cwd is deeper than the
  -- repository's project. In a worktree, which lies outside the main
  -- checkout, lengths compare with the worktree's own top folder.
  if best ~= nil and best ~= repo then
    local top = toplevel(cwd)
    if top ~= nil and #best > #top then return best end
  end
  return repo
end

-- listed returns the paths of the listed projects: the added ones, then the
-- scanned ones that Remove Project has not hidden. It also returns the set
-- of the added ones whose folder is missing; a scanned one is there.
local function listed()
  local s = load_state()
  local seen, paths = {}, {}
  for _, p in ipairs(s.hidden) do seen[p] = true end
  for _, p in ipairs(s.projects) do seen[p] = nil end
  for _, list in ipairs({ s.projects, scan() }) do
    for _, p in ipairs(list) do
      if not seen[p] then seen[p] = true; paths[#paths + 1] = p end
    end
  end
  return paths, missing(s.projects)
end

-- project_rows returns the rows of the project picker: the listed projects,
-- then the row that adds a project. The project that
-- holds cwd, the folder of the terminal the action was run from, goes
-- first. Then, with project_order "recent", the most recently used go first
-- and the rest by name; with "name" all go by name. Missing ones go last.
local function project_rows(cwd)
  local s = load_state()
  local paths, gone = listed()
  local rank = {}
  local focused = containing(paths, cwd)
  if focused ~= nil then rank[focused] = 0 end
  if config.project_order ~= "name" then
    for i, p in ipairs(s.recent) do
      if rank[p] == nil then rank[p] = i end
    end
  end
  table.sort(paths, function(a, b)
    local ra, rb = rank[a], rank[b]
    if ra ~= nil or rb ~= nil then
      if ra == nil then return false end
      if rb == nil then return true end
      if ra ~= rb then return ra < rb end
    end
    local na, nb = basename(a):lower(), basename(b):lower()
    if na ~= nb then return na < nb end
    return a < b
  end)
  local rows = rows_of(paths, gone)
  rows[#rows + 1] = { id = ADD_PROJECT, title = "Add project…", subtitle = "Choose a folder", icon = "plus" }
  return rows
end

-- subfolders lists the folders directly inside dir as { path = ..., repo =
-- boolean }, sorted by name, hidden folders left out. It returns an empty list
-- for a folder it cannot read.
local function subfolders(dir)
  local list = {}
  -- -print0 ends each path with NUL, the one byte a path cannot hold.
  local out = output({ "find", dir, "-mindepth", "1", "-maxdepth", "1", "-type", "d",
    "-not", "-name", ".*", "-print0" })
  local repos = {}
  for _, path in ipairs(repos_in(dir)) do repos[path] = true end
  if out ~= nil then
    for path in out:gmatch("[^%z]+") do
      list[#list + 1] = { path = path, repo = repos[path] == true }
    end
  end
  table.sort(list, function(a, b) return basename(a.path):lower() < basename(b.path):lower() end)
  return list
end

-- parent_of returns the folder above dir, or nil at the top.
local function parent_of(dir)
  local parent = dir:match("^(.*)/[^/]+/?$")
  if parent == nil or parent == "" then
    if dir:match("^/[^/]+/?$") then return "/" end
    return nil
  end
  return parent
end

-- save_project shows path again if Remove Project hid it, else adds it to
-- the list once, and returns it. A project a root finds needs no entry.
local function save_project(path)
  local s = load_state()
  for i, p in ipairs(s.hidden) do
    if p == path then table.remove(s.hidden, i); break end
  end
  local saved = false
  for _, p in ipairs(s.projects) do
    if p == path then saved = true; break end
  end
  if not saved then
    for _, p in ipairs(scan()) do
      if p == path then saved = true; break end
    end
  end
  if not saved then s.projects[#s.projects + 1] = path end
  save_state()
  return path
end

---------------------------------------------------------------------------
-- Branches and checkouts
---------------------------------------------------------------------------

-- rex.ui.pick takes at most this many rows, and raises on more.
local MAX_ROWS = 2000

-- row_list returns an empty list of branch rows and the function that adds
-- one. A row's id is its branch name ("origin/x" for a remote branch), so a
-- typed name and a chosen row mean the same branch. A name that is already
-- listed is left out, and so is every row past the most the picker takes:
-- rex.ui.pick raises on both. A branch that fell off the end can be typed.
local function row_list()
  local rows, seen = {}, {}
  return rows, function(name, subtitle, icon)
    if seen[name] or #rows >= MAX_ROWS then return end
    seen[name] = true
    rows[#rows + 1] = { id = name, title = name, subtitle = subtitle, icon = icon or "branch" }
  end
end

-- checkouts describes the repository of a project, or returns nil and git's
-- message for a folder with none:
--   current  the branch checked out in the project's own folder, the main
--            checkout; nil when HEAD is detached
--   top      the project's own folder as git spells it
--   others   its other checkouts, the worktrees
--   taken    each branch that a worktree holds, with that worktree
local function checkouts(project)
  local trees, err = worktrees(project)
  if trees == nil then return nil, err end
  -- Git lists every checkout, the project's own among them. Find that one by
  -- its top folder as git spells it. With no match it is the first.
  local top = toplevel(project)
  local own = 1
  for i, tree in ipairs(trees) do
    if tree.path == top then own = i; break end
  end
  local c = { current = current_branch(project), top = trees[own].path, others = {}, taken = {} }
  for i, tree in ipairs(trees) do
    if i ~= own then
      c.others[#c.others + 1] = tree
      if tree.branch then c.taken[tree.branch] = tree end
    end
  end
  -- Git lists worktrees by folder name, which need not be the branch's.
  if config.branch_order == "name" then
    table.sort(c.others, function(a, b)
      local na, nb = a.branch or "", b.branch or ""
      if na ~= nb then return na < nb end
      return a.path < b.path
    end)
  end
  return c
end

-- add_branches adds, after a flow's own first rows, the regular branches,
-- the local ones that are neither the main checkout's nor held by a
-- worktree, then the remote branches. A remote branch is listed while no
-- local branch has its name, once for each remote that has it.
local function add_branches(project, c, add)
  local locals = {}
  for _, name in ipairs(local_branches(project)) do
    locals[name] = true
    if name ~= c.current and not c.taken[name] then add(name) end
  end
  for _, remote in ipairs(remote_branches(project)) do
    if not locals[remote.branch] then add(remote.name) end
  end
end

-- add_current adds the row of the main checkout's branch.
local function add_current(c, add)
  if c.current then add(c.current, "current branch") else add("HEAD", "detached") end
end

-- here_rows returns the branches Switch Branch offers: the main checkout's
-- branch, then every other regular branch, then the remote branches.
local function here_rows(project, c)
  local rows, add = row_list()
  add_current(c, add)
  add_branches(project, c, add)
  return rows
end

-- worktree_rows returns the branches Open Worktree offers: the worktrees,
-- then the regular branches, then the remote ones. The main checkout's
-- branch is not listed: it cannot get a worktree.
local function worktree_rows(project, c)
  local rows, add = row_list()
  for _, tree in ipairs(c.others) do
    -- A worktree whose folder is gone can only be cleaned up.
    if tree.branch and not tree.prunable then
      add(tree.branch, short(tree.path), "folder")
    end
  end
  add_branches(project, c, add)
  return rows
end

-- cleanup_rows returns the branches Clean Up offers: the worktrees, those
-- whose folder is gone too, then the regular branches. The main checkout's
-- branch cannot be deleted, and a remote branch is not Clean Up's to delete.
local function cleanup_rows(project, c)
  local rows, add = row_list()
  for _, tree in ipairs(c.others) do
    if tree.branch then add(tree.branch, short(tree.path), "folder") end
  end
  for _, name in ipairs(local_branches(project)) do
    if name ~= c.current and not c.taken[name] then add(name) end
  end
  return rows
end

-- default_base returns the name of what a new branch starts from by
-- default: the base setting, else the default branch that wt finds (wt
-- config state default-branch), else nil. wt keeps what it found in
-- git config (worktrunk.default-branch). Before that it reads
-- <remote>/HEAD, then asks the remote, then guesses from the local
-- branches; see wt_in for how a remote host skips asking.
local function default_base(project)
  if config.base then return config.base end
  local r = wt_in(project, false, "config", "state", "default-branch")
  if r == nil or not r.ok then return nil end
  local name = trim(r.stdout)
  return name ~= "" and name or nil
end

-- default_remote_base returns the remote branch of the default base, as
-- { name = "origin/main", remote = "origin", branch = "main" }, or nil when
-- it has none. That is the branch the local one follows, else the base
-- itself when it is written as a remote branch, else the branch of that
-- name on origin, else on the first remote that has it. Only one that was
-- fetched before counts, so that the row names something.
local function default_remote_base(project)
  local base = default_base(project)
  if base == nil then return nil end
  local remote, branch = nil, nil
  if has_ref(project, "refs/heads/" .. base) then
    local r = git_text(project, "config", "--get", "branch." .. base .. ".remote")
    local m = git_text(project, "config", "--get", "branch." .. base .. ".merge")
    -- A remote of "." is the repository itself.
    if r ~= "" and r ~= "." and m:find("^refs/heads/") then
      remote, branch = r, m:sub(#"refs/heads/" + 1)
    end
  end
  if remote == nil then
    for _, r in ipairs(remote_branches(project)) do
      -- A base setting may name the remote branch itself: origin/main.
      if r.name == base then
        remote, branch = r.name:sub(1, #r.name - #r.branch - 1), r.branch
        break
      end
      if r.branch == base then
        local name = r.name:sub(1, #r.name - #base - 1)
        if remote == nil or name == "origin" then remote = name end
        branch = base
      end
    end
  end
  if remote == nil or not has_ref(project, "refs/remotes/" .. remote .. "/" .. branch) then return nil end
  return { name = remote .. "/" .. branch, remote = remote, branch = branch }
end

-- base_rows returns the rows that say what a new branch starts from: the
-- default base, the main checkout's branch, then every other branch, the
-- remote ones included. A default base with a remote branch is listed as
-- that remote branch, which is fetched before the new branch starts there;
-- the local branch is listed with the others.
local function base_rows(project, c)
  local rows, add = row_list()
  local fetched = default_remote_base(project)
  if fetched ~= nil then
    add(fetched.name, "default · fetched first")
  else
    -- Leave the default out where there is none or it names nothing, such
    -- as a base setting of "develop" in a repository without one, so that
    -- Return on the first row always works. The default may be any commit,
    -- so rev-parse reads it.
    local base = default_base(project)
    if base ~= nil and git(project, "rev-parse", "--verify", "--quiet", base .. "^{commit}") ~= nil then
      add(base, "default")
    end
  end
  add_current(c, add)
  for _, name in ipairs(local_branches(project)) do add(name) end
  for _, remote in ipairs(remote_branches(project)) do add(remote.name) end
  return rows
end

-- switch_worktree runs wt switch in project, with args naming what to
-- switch to: a branch, a remote branch such as origin/x, --create and
-- --base for a new branch, or pr:<number>. wt goes to the branch's worktree,
-- or makes one, and makes the local branch when there is none. how is
-- "hooks" for the user's own branches: their hooks run, and wt's approval of
-- a project's hooks decides, as in a terminal. Else no hook runs, since the
-- hooks of a pull request come from whoever wrote it, and how is "network"
-- when wt fetches, as it does for a pull request, or "local".
--
-- It returns { dir, branch }: the checkout's folder as git spells it, and
-- its branch. Else it returns nil and wt's message, and true as well when wt
-- was stopped for taking too long.
local function switch_worktree(project, how, ...)
  local r, err, stopped
  if how == "hooks" then
    r, err, stopped = wt(project, "hooks", "switch", "--no-cd", "--format=json",
      "--config-set", worktree_path(), ...)
  else
    r, err, stopped = wt(project, how == "network", "switch", "--no-cd", "--no-hooks", "--format=json",
      "--config-set", worktree_path(), ...)
  end
  if r == nil then return nil, err, stopped end
  local co = { dir = tostring(r.path or ""), branch = r.branch }
  -- wt may spell the folder differently from git (a symlink such as /tmp),
  -- and the rest of this file, the remembered sessions too, goes by git's
  -- spelling.
  for _, tree in ipairs(worktrees(project) or {}) do
    if co.branch ~= nil and tree.branch == co.branch then co.dir = tree.path; break end
  end
  return co
end

-- pr_mark says whether branch was opened for a pull request: Review Pull
-- Request marks it with branch.<name>.rex-pr.
local function pr_mark(project, branch)
  return git_text(project, "config", "--get", "branch." .. branch .. ".rex-pr") ~= ""
end

-- switch_branch checks branch out in the project's own folder. Without
-- base, the branch exists already. With base, the branch is new and starts
-- there, and track ("--track", "--no-track", or nil for what git does by
-- itself) says whether it follows base. It returns true, or nil and git's
-- message.
local function switch_branch(project, branch, base, track)
  local args = { "switch" }
  if base ~= nil then
    args[#args + 1] = "-c"
    args[#args + 1] = branch
    if track ~= nil then args[#args + 1] = track end
    args[#args + 1] = base
  else
    args[#args + 1] = branch
  end
  local _, err = git(project, unpack(args))
  if err ~= nil then return nil, err end
  return true
end

-- record_at returns the record of the checkout in folder while the folder is
-- there. A record whose folder is gone is dropped and saved.
local function record_at(folder)
  local sessions = load_state().sessions
  local record = sessions[folder]
  if record == nil or is_folder(folder) then return record end
  sessions[folder] = nil
  save_state()
  return nil
end

-- inside says whether the folder cwd is in the checkout at dir. In a
-- repository both must have the same top folder, which keeps a worktree made
-- inside another checkout apart from it. A plain folder goes by its path.
local function inside(cwd, dir, repo)
  if repo then
    local top = toplevel(cwd)
    return top ~= nil and top == toplevel(dir)
  end
  local a, b = real(cwd), real(dir)
  return a == b or a:sub(1, #b + 1) == b .. "/"
end

-- landing answers an open op with where to work: the checkout's folder, the
-- label of its session, the session remembered for it, the shell a new
-- session starts (nil for the account's default), and adopt, which says
-- whether the session the action was run from may become the checkout's
-- session. It may when its terminal is inside the checkout and it is not
-- already the session of another checkout. It also answers the project's
-- name, the branch checked out in dir (nil for a plain folder or a detached
-- HEAD) and pr, the number of the pull request reviewed, for the label and
-- layout settings.
local function landing(dir, label, a, repo, pr)
  local sessions = load_state().sessions
  local adopt = a.from ~= nil and a.cwd ~= nil and inside(a.cwd, dir, repo)
  if adopt then
    for folder, record in pairs(sessions) do
      if record.session == a.from and folder ~= dir and record_at(folder) then adopt = false end
    end
  end
  local record = sessions[dir]
  return { dir = dir, label = label, session = record and record.session, adopt = adopt,
    shell = config.shell, project = basename(a.project),
    branch = repo and current_branch(dir) or nil, pr = pr }
end

---------------------------------------------------------------------------
-- The backend: the work done where the projects are
---------------------------------------------------------------------------

-- The pickers run in the app's own server, the one on the machine the app
-- runs on, because the app only lists and binds that server's actions. The
-- projects live on the server that holds the focused session, which can be a
-- remote host. So each step that reads folders or runs git is an op of the
-- projects_backend action, and the pickers ask for it either directly or,
-- for a remote session, through client.action on that server. Ops never ask
-- the person anything: a call to another server has 10 seconds to answer.
-- Their results travel as JSON, so they hold only strings, numbers,
-- booleans and tables. An op that git turns down answers { why = git's message }
-- instead of raising, so that the message arrives as git wrote it.
local backend = {}

-- start_dir is the folder the Add project browser opens in: the first root,
-- else the home folder.
local function start_dir()
  local first = config.roots[1]
  local dir = first and expand(first) or home
  if dir == "" or not is_folder(dir) then dir = "/" end
  return dir
end

-- projects returns the rows of the project picker. a.cwd is the folder of
-- the terminal the action was run from, whose project goes first.
function backend.projects(a)
  return { rows = project_rows(a.cwd) }
end

-- browse returns one page of the Add project browser: the folder dir, or the
-- start folder without one. repos names the rows that are repositories.
function backend.browse(a)
  local dir = a.dir or start_dir()
  dir = dir:gsub("/+$", "")
  if dir == "" then dir = "/" end
  local parent = parent_of(dir)
  local rows = {
    { id = ADD_HERE, title = "Add " .. (dir == "/" and "/" or basename(dir)), subtitle = short(dir), icon = "plus" },
  }
  if parent ~= nil then
    rows[#rows + 1] = { id = UP, title = "..", subtitle = short(parent), icon = "folder" }
  end
  local repos = {}
  for _, child in ipairs(subfolders(dir)) do
    if child.repo then repos[child.path] = true end
    rows[#rows + 1] = { id = child.path, title = basename(child.path), icon = "folder" }
  end
  return {
    dir = dir,
    parent = parent,
    placeholder = short(dir) .. "/  (type a path to jump)",
    rows = rows,
    repos = repos,
  }
end

-- typed reads a path the person typed. A path that does not start at the
-- root or at ~ is inside a.dir, the folder being browsed, or the start folder
-- without one. A folder answers { dir, repo }. Anything else answers the
-- nearest folder above it that exists and, as rest, the name that was not
-- found in it, so that the browser can open there with rest as its filter.
-- why is set when nothing was typed or no folder above the path exists.
function backend.typed(a)
  local path = expand(a.text or "")
  if path == "" then return { why = "nothing was typed" } end
  if path:sub(1, 1) ~= "/" then
    local base = a.dir or start_dir()
    path = (base == "/" and "" or base:gsub("/+$", "")) .. "/" .. path
  end
  if #path > 1 then path = path:gsub("/+$", "") end
  if is_folder(path) then return { dir = path, repo = is_repo_root(path) } end
  local dir, rest = parent_of(path), basename(path)
  while dir ~= nil and not is_folder(dir) do
    dir, rest = parent_of(dir), basename(dir)
  end
  if dir == nil then return { why = "not a folder: " .. path } end
  return { dir = dir, rest = rest }
end

-- add puts path on the project list.
function backend.add(a)
  return { path = save_project(a.path) }
end

-- here_rows returns the rows of Switch Branch's branch list for a.project.
-- A folder with no repository has no branches, and answers plain = true.
function backend.here_rows(a)
  local c = checkouts(a.project)
  if c == nil then return { plain = true } end
  return { rows = here_rows(a.project, c) }
end

-- worktree_rows returns the rows of Open Worktree's branch list for
-- a.project. A folder with no repository has no branches, and answers
-- plain = true.
function backend.worktree_rows(a)
  local c = checkouts(a.project)
  if c == nil then return { plain = true } end
  return { rows = worktree_rows(a.project, c) }
end

-- name says what the branch a.name, typed or picked in a.project, is:
--   { name }        a branch there is (local, remote, or the main
--                   checkout's), one of wt's shortcuts ^ and -, or a pull
--                   request; the open ops take it or say why not
--   { name, rows }  a new branch: the name as git will get it, and the rows
--                   to choose its base from
--   { why }         no name was given, git does not take it, or the folder is
--                   no repository
-- It makes nothing.
function backend.name(a)
  local c, unreadable = checkouts(a.project)
  if c == nil then return { why = unreadable } end
  local t, why = typed_name(a.project, c, a.name)
  if t == nil then return { why = why } end
  if t.kind ~= "new" then return { name = t.name } end
  return { name = t.name, rows = base_rows(a.project, c) }
end

-- cleanup_rows returns the rows of Clean Up's branch list for a.project, or
-- why with what git said about a folder with no repository, or why there is
-- nothing to clean up.
function backend.cleanup_rows(a)
  local c, unreadable = checkouts(a.project)
  if c == nil then return { why = unreadable } end
  local rows = cleanup_rows(a.project, c)
  if #rows == 0 then return { why = basename(a.project) .. " has no branch to clean up" } end
  return { rows = rows }
end

-- prepare reads the repository of a.project and the branch a.name for an
-- open op. It answers the checkouts and the name as typed_name reads it, or
-- nil and the op's answer: the landing of a plain folder, which is one place
-- to work, or why the name names no branch.
local function prepare(a)
  local c = checkouts(a.project)
  if c == nil then return nil, landing(a.project, basename(a.project), a, false) end
  local t, why = typed_name(a.project, c, a.name)
  if t == nil then return nil, { why = why } end
  return c, t
end

-- new_base checks base, what a new branch of project starts from, and
-- fetches it when it is the default base. It answers base, or nil and why.
local function new_base(project, base)
  base = trim(base or "")
  if base == "" then return nil, "no base was named" end
  -- Git would read a base that starts with a dash as an option.
  if base:sub(1, 1) == "-" then return nil, "not a branch or a commit: " .. base end
  -- The default base starts from what its remote has now. Every other
  -- base is taken as it is here, unpushed commits and all.
  local fetched = default_remote_base(project)
  if fetched ~= nil and base == fetched.name then
    local _, failed = git_net(project, "fetch", "--quiet", fetched.remote, fetched.branch)
    if failed ~= nil then return nil, failed end
  end
  return base
end

-- elsewhere says why Switch Branch does not take t, a shortcut or a pull
-- request, and what does.
local function elsewhere(t)
  if t.kind == "pr" then
    return t.name .. " is a pull request, which Switch Branch does not open: use Review Pull Request"
  end
  local what = t.name == "^" and "the default branch" or "the previous branch"
  return t.name .. " is wt's shortcut for " .. what ..
    ", which Switch Branch does not take: type the branch's name, or use Open Worktree"
end

local function switch_checkout(a)
  local c, t = prepare(a)
  if c == nil then return t end
  local project, title = a.project, basename(a.project)
  if t.kind == "shortcut" or t.kind == "pr" then return { why = elsewhere(t) } end
  if t.kind == "current" then return landing(project, title, a, true) end
  local branch, base, track = t.name, nil, nil
  if t.kind == "remote" then branch, base, track = t.branch, t.name, "--track" end
  if t.kind == "new" then
    local why
    base, why = new_base(project, a.base)
    if base == nil then return { why = why } end
    -- A new branch here does not follow the remote branch it starts from,
    -- however that branch was written: origin/x, remotes/origin/x. wt makes
    -- a worktree's branch follow one of its own name.
    local full = git(project, "rev-parse", "--symbolic-full-name", base)
    if full ~= nil and full:find("^refs/remotes/") then track = "--no-track" end
  end
  local ok, err = switch_branch(project, branch, base, track)
  if not ok then return { why = err } end
  return landing(project, title, a, true)
end

local review_checkout

local function worktree_checkout(a)
  local c, t = prepare(a)
  if c == nil then return t end
  local project, title = a.project, basename(a.project)
  if t.kind == "pr" then return review_checkout(a, t.pr) end
  if t.kind == "current" then return landing(project, title, a, true) end
  local tree = t.kind == "local" and c.taken[t.name] or nil
  if tree ~= nil and not tree.prunable then
    return landing(tree.path, title .. " · " .. t.name, a, true)
  end
  -- Hooks run for the user's own branches, not for a pull request's, by its
  -- mark, nor for wt's shortcuts.
  local branch = t.kind == "remote" and t.branch or t.name
  local how = (t.kind ~= "shortcut" and not pr_mark(project, branch)) and "hooks" or "local"
  local co, err, stopped
  if t.kind == "new" then
    local base, why = new_base(project, a.base)
    if base == nil then return { why = why } end
    co, err, stopped = switch_worktree(project, how, "--create", t.name, "--base", base)
  else
    -- A remote branch goes by its own name, origin/x, and wt makes x. wt
    -- reads ^ and - itself.
    co, err, stopped = switch_worktree(project, how, t.name)
  end
  if co == nil and stopped and how == "hooks" then
    err = err .. ". A wt hook may have held it: open " .. branch .. " again to go to the worktree wt made"
  end
  if co == nil then return { why = err } end
  -- A name wt answers with the main checkout, such as ^ or origin/main, is
  -- the main checkout.
  if co.dir == c.top then return landing(project, title, a, true) end
  return landing(co.dir, title .. " · " .. (co.branch or t.name), a, true)
end

-- switch_here switches the project's own folder to the branch a.name and
-- says where to work. The name is read as typed_name reads it: the main
-- checkout's branch, a local branch, a remote one ("origin/x", which becomes
-- a local branch "x" that tracks it), or a new branch, which starts from
-- a.base, which name offers rows for. wt's shortcuts ^ and -, and pull
-- requests, are refused with what takes them. a.from is the session the action was
-- run from and a.cwd the folder of its terminal.
--
-- It answers one of
--   { dir, label, session, adopt, ... }  where to work; see landing
--   { why }                              git said no, and nothing further changed
--
-- A project whose checkout is ready goes first on the recent list.
function backend.switch_here(a)
  local r = switch_checkout(a)
  if r.dir ~= nil then mark_used(a.project) end
  return r
end

-- open_worktree makes the worktree of the branch a.name ready and says where
-- it is. The name is read as typed_name reads it: the main checkout's
-- branch, which is the project's own folder, a branch a worktree holds, a
-- local branch, a remote one ("origin/x", which becomes a local branch "x"
-- that tracks it), or a new branch, which starts from a.base, which name
-- offers rows for. wt reads its shortcuts ^ (the default branch) and - (its
-- previous branch) itself, and a pull request, pr:N or a link, opens as
-- Review Pull Request opens it. a.from is the session the action was run from and
-- a.cwd the folder of its terminal.
--
-- It answers one of
--   { dir, label, session, adopt, ... }  where to work; see landing
--   { why }                              git or wt said no, or no branch or base was named,
--                                        and nothing further changed
--
-- A project whose checkout is ready goes first on the recent list.
function backend.open_worktree(a)
  local r = worktree_checkout(a)
  if r.dir ~= nil then mark_used(a.project) end
  return r
end

-- keep remembers a.session as the session of the checkout in a.dir, and
-- a.created, whether rex-projects made it.
function backend.keep(a)
  local sessions = load_state().sessions
  for folder, record in pairs(sessions) do
    if record.session == a.session then sessions[folder] = nil end
  end
  sessions[a.dir] = { session = a.session, created = a.created == true }
  save_state()
  return {}
end

-- folder_of returns the key of the record of the checkout at path, matched
-- also through symbolic links and when the folder is gone, or nil. A
-- worktree's record goes by git's spelling, every link followed, so path is
-- spelled that way too.
local function folder_of(path)
  local sessions = load_state().sessions
  if sessions[path] ~= nil then return path end
  local want = spelled(path)
  if sessions[want] ~= nil then return want end
  return nil
end

-- forget_record forgets the record of the checkout at a.path, without
-- checking its folder, and answers { record }, or {} when there is none.
function backend.forget_record(a)
  local path = type(a.path) == "string" and expand(a.path):gsub("/+$", "") or ""
  if path == "" then return {} end
  local folder = folder_of(path)
  if folder == nil then return {} end
  local record = load_state().sessions[folder]
  load_state().sessions[folder] = nil
  save_state()
  return { record = record }
end

-- kept says why wt kept a branch, for each branch_outcome of wt remove that
-- Force delete cannot change.
local kept = {
  retained_checked_out = "another worktree has it checked out",
  retained_raced = "it moved while its worktree was removed; clean up again",
  retained_failed = "git could not delete it",
  not_attempted = "wt did not try to delete it",
}

-- cleanup removes the branch a.branch of a.project with wt remove: first its
-- worktree, when it has one, then the branch, when it adds nothing to the
-- default branch (squash and rebase merges count; see wt remove --help). wt
-- will not remove a worktree with changed or untracked files, and nothing
-- changes; ignored files do not count. A worktree whose folder is gone is
-- pruned.
-- With a.force, wt remove -D deletes the branch whatever it holds.
--
-- The hooks of the user's own branches run; a branch marked for a pull
-- request runs none.
--
-- It answers
--   { why }              the worktree, when there was one, is still there,
--                        and why wt failed
--   { record, failed }   the worktree is gone, yet wt failed, said why in
--                        failed, or was stopped; record as below
--   { record, kept }     record is the one kept for the worktree, now gone
--                        from git's list and its record forgotten, for the
--                        caller's close path, or nil. kept, when the branch
--                        stays, is { reason, force }: force says whether
--                        Force delete would delete it.
function backend.cleanup(a)
  local project, branch = a.project, a.branch
  local c, unreadable = checkouts(project)
  if c == nil then return { why = unreadable } end
  local tree = c.taken[branch]
  local marked = pr_mark(project, branch)
  -- --delete-branch wins over a [remove] delete-branch = false in wt's
  -- config.
  local args = { "remove", "--foreground", "--format=json", "--delete-branch" }
  if marked then table.insert(args, 3, "--no-hooks") end
  if a.force then args[#args + 1] = "-D" end
  args[#args + 1] = branch
  local r, err
  if marked then
    r, err = wt_in(project, false, unpack(args))
  else
    r, err = wt_hooked(project, unpack(args))
  end
  -- wt exits 1 when git fails to delete the branch, yet answers what it
  -- removed. A refusal answers nothing.
  local list, outcome, why = nil, nil, err
  if r ~= nil then
    list = decode(r.stdout)
    outcome = list and type(list[1]) == "table" and list[1].branch_outcome or nil
    if not r.ok and outcome == nil then
      why = wt_why(project, r)
    elseif list == nil then
      why = "wt did not answer with JSON: " .. trim(r.stdout)
    end
  end

  -- Whatever wt answered, the worktree is gone when git no longer lists it,
  -- its folder deleted by hand or not, and only then is its record forgotten.
  local record, gone = nil, false
  if tree ~= nil then
    local now = worktrees(project)
    gone = now ~= nil
    for _, other in ipairs(now or {}) do
      if other.path == tree.path then gone = false; break end
    end
    if gone then record = backend.forget_record{ path = tree.path }.record end
  end
  if why ~= nil then
    if gone then return { record = record, failed = why } end
    return { why = why }
  end

  if outcome == "deleted" then return { record = record } end
  if outcome == "retained_unmerged" and not a.force then
    return { record = record,
      kept = { reason = branch .. " has changes that the default branch lacks", force = true } }
  end
  return { record = record, kept = {
    reason = "wt kept " .. branch .. ": " .. (kept[outcome] or tostring(outcome)), force = false } }
end

-- saved returns the rows of the listed projects, for Remove Project, the
-- missing ones last.
function backend.saved()
  return { rows = rows_of(listed()) }
end

-- bare is dir without a trailing slash, / itself kept.
local function bare(dir)
  dir = dir:gsub("/+$", "")
  return dir == "" and "/" or dir
end

-- forget takes project off the list. A project a root finds is hidden
-- instead, until it is added again. Hidden projects under no root that is
-- set now are dropped.
function backend.forget(a)
  local s = load_state()
  local hide = false
  for _, p in ipairs(scan()) do
    if p == a.project then hide = true; break end
  end
  for _, p in ipairs(s.hidden) do
    if p == a.project then hide = false; break end
  end
  if hide then s.hidden[#s.hidden + 1] = a.project end
  local roots = {}
  for _, root in ipairs(config.roots) do roots[bare(expand(root))] = true end
  local kept = {}
  for _, p in ipairs(s.hidden) do
    local parent = parent_of(p)
    if parent ~= nil and roots[bare(parent)] then kept[#kept + 1] = p end
  end
  s.hidden = kept
  for i, p in ipairs(s.projects) do
    if p == a.project then table.remove(s.projects, i); break end
  end
  for i, p in ipairs(s.recent) do
    if p == a.project then table.remove(s.recent, i); break end
  end
  s.sessions[a.project] = nil
  save_state()
  return {}
end

---------------------------------------------------------------------------
-- Pull requests
---------------------------------------------------------------------------

-- wt switch pr:<number> makes or finds the checkout of a pull request. Each
-- branch Review Pull Request opens then carries a setting in the
-- repository's config: branch.<name>.rex-pr, the number of its pull request.
-- Git drops it when it deletes the branch.

-- gh runs the GitHub CLI in project and returns what it printed as JSON,
-- decoded, or nil and why.
local function gh(project, ...)
  local r, err = rex.exec({ "gh", ... }, tool_opts({ cwd = project, timeout = net_timeout() }))
  if r ~= nil and r.timed_out then return nil, timed_out("gh") end
  if r == nil or r.code == 127 then
    return nil, "gh did not run (" .. tostring(err or trim(r and r.stderr or "")) ..
      "). Review Pull Request needs the GitHub CLI on PATH (the login shell's)."
  end
  if not r.ok then return nil, or_status(trim(r.stderr), "gh", r) end
  local decoded = decode(r.stdout)
  if decoded == nil then return nil, "gh did not answer with JSON" end
  return decoded
end

-- owner_repo reads the owner/repo that a repository's address ends in, in
-- lower case, or nil: https://github.com/Acme/App.git, git@work:acme/app and
-- acme/app itself all read acme/app.
local function owner_repo(url)
  url = trim(url):gsub("/+$", ""):gsub("%.git$", "")
  local path = url:match("([^/:]+/[^/:]+)$")
  return path and path:lower() or nil
end

-- wrong_link says why typed, a link to a pull request, is not one of
-- project's, or returns nil for a link that is, and for a number. wt reads
-- only the number of a link and looks for it in the repository gh is set
-- to (gh repo set-default), else in a remote's. So the link's repository
-- must be that one, else one of the remotes.
local function wrong_link(project, typed)
  local linked = owner_repo(tostring(typed):match("^(.*)/pull/%d+") or "")
  if linked == nil then return nil end
  local title = basename(project)
  -- set-default --view reads git config, not the network.
  local r = rex.exec({ "gh", "repo", "set-default", "--view" },
    tool_opts({ cwd = project, timeout = net_timeout() }))
  local default = r ~= nil and r.ok and owner_repo(r.stdout) or nil
  if default ~= nil then
    if default == linked then return nil end
    return "that link is to a pull request of " .. linked .. ", and gh looks in " .. default ..
      " for those of " .. title .. " (gh repo set-default)"
  end
  local names = git(project, "remote") or ""
  for name in names:gmatch("[^\r\n]+") do
    if owner_repo(git(project, "remote", "get-url", name) or "") == linked then return nil end
  end
  return "that link is to a pull request of " .. linked .. ", which is no remote of " .. title
end

-- pr_branches maps each pull request number to the branch Review made for it.
local function pr_branches(project)
  local map = {}
  local out = git(project, "config", "--get-regexp", "^branch\\..*\\.rex-pr$") or ""
  for line in out:gmatch("[^\r\n]+") do
    local branch, number = line:match("^branch%.(.+)%.rex%-pr (%d+)$")
    if branch then map[tonumber(number)] = branch end
  end
  return map
end

-- pulls returns the rows of the pull request list of a.project: those whose
-- review is asked of you first, then the rest, each newest first.
function backend.pulls(a)
  local project = a.project
  local c, unreadable = checkouts(project)
  if c == nil then return { why = unreadable } end
  local list, err = gh(project, "pr", "list", "--state", "open", "--limit", "500",
    "--json", "number,title,headRefName,author,isDraft")
  if list == nil then return { why = err } end
  -- With none open the list is empty, and a number or a link can still be
  -- typed: a closed pull request can be reviewed too.
  if #list == 0 then return { rows = {} } end
  -- Asked of you, teams included. Without an answer, none is first.
  local asked = {}
  local mine = gh(project, "pr", "list", "--state", "open", "--limit", "500",
    "--search", "review-requested:@me", "--json", "number")
  for _, p in ipairs(mine or {}) do asked[p.number] = true end
  local held = pr_branches(project)
  local first, rest = {}, {}
  for _, p in ipairs(list) do
    local bits = { p.headRefName }
    if type(p.author) == "table" and p.author.login then bits[#bits + 1] = "@" .. p.author.login end
    if p.isDraft then bits[#bits + 1] = "draft" end
    if asked[p.number] then bits[#bits + 1] = "review requested" end
    local branch = held[p.number]
    local tree = branch and c.taken[branch]
    local row = {
      id = "#" .. p.number,
      title = "#" .. p.number .. " " .. tostring(p.title),
      subtitle = table.concat(bits, " · "),
      -- A pull request with a worktree already looks like one.
      icon = (tree and not tree.prunable) and "folder" or "branch",
    }
    if asked[p.number] then first[#first + 1] = row else rest[#rest + 1] = row end
  end
  local rows = {}
  for _, group in ipairs({ first, rest }) do
    for _, row in ipairs(group) do
      if #rows < MAX_ROWS then rows[#rows + 1] = row end
    end
  end
  return { rows = rows }
end

-- review_checkout makes the checkout of the pull request typed, a number or
-- a link, in a.project ready with wt switch pr:<number> and says where it
-- is, as the open ops do, or answers { why }.
-- wt names the branch after the pull request's branch, and for one from a
-- fork sets it to push there; a branch of that name that is there already
-- is opened as it is. A pull request of the main checkout's branch opens in
-- the main checkout. A checkout that was there already stays at the commit
-- it is at: bringing it up to the pull request is git's to do.
function review_checkout(a, typed)
  local project = a.project
  local title = basename(project)
  local n = pr_number(typed)
  if n == nil then return { why = "not a pull request: " .. tostring(typed) } end
  local c, unreadable = checkouts(project)
  if c == nil then return { why = unreadable } end
  local wrong = wrong_link(project, typed)
  if wrong ~= nil then return { why = wrong } end
  -- On another host, have wt find the default branch off the network
  -- first: the switch below may use the network, and so may wt to find it.
  if net_limit ~= nil then wt_in(project, false, "config", "state", "default-branch") end
  local co, err = switch_worktree(project, "network", "pr:" .. n)
  if co == nil then return { why = err } end
  if co.branch ~= nil then
    git(project, "config", "branch." .. co.branch .. ".rex-pr", tostring(n))
  end
  if co.dir == c.top then return landing(project, title, a, true, n) end
  return landing(co.dir, title .. " · #" .. n, a, true, n)
end

function backend.review(a)
  local r = review_checkout(a, a.pr)
  if r.why == nil then mark_used(a.project) end
  return r
end

-- The app cannot hide an action, so this one sits in a category of its own,
-- away from the ones a person runs.
rex.action{
  name = "projects_backend",
  title = "Projects: Backend",
  description = "Used by the Projects actions to read folders and run git where the projects are",
  category = "Internal",
  args = { op = "string?", args = "object?", relayed = "boolean?" },
  run = function(_, args)
    -- Run from the palette, it has no op and does nothing.
    if args == nil or args.op == nil then return end
    local op = backend[args.op]
    if op == nil then error("projects_backend: unknown op " .. tostring(args.op), 0) end
    login_env()
    -- Asked for by another server, which waits only so long: see net_limit.
    if args.relayed then
      net_limit = { by = os ~= nil and os.time ~= nil and (os.time() + NET_SECONDS) or nil }
    end
    local ok, result = pcall(op, args.args or {})
    net_limit = nil
    if not ok then error(result, 0) end
    return result
  end,
}

---------------------------------------------------------------------------
-- The actions
---------------------------------------------------------------------------

-- fail ends an action for why. A person who cancelled, or no reason, ends it
-- quietly. Any other reason, such as git's own words or a palette that
-- failed, is the message for the person: the app shows an action's error, so
-- it is raised as one, on one line.
local function fail(why)
  if why == nil or why == "cancelled" then return end
  error(one_line(why), 0)
end

-- connect returns the function that runs a backend op where the projects of
-- ctx's session are, and the table whose call reaches that server.
local function connect(ctx)
  local host = ctx and ctx.server
  if host == nil then
    return function(op, args) return backend[op](args or {}) end, rex
  end
  local server = rex.server(host)
  return function(op, args)
    local r, err = server.call("client.action", {
      action = "projects_backend",
      args = { op = op, args = args or {}, relayed = true },
    })
    if r == nil then
      err = tostring(err)
      if err:find("not.found") then
        err = err .. " (is projects.lua in init.lua on " .. host .. "?)"
      end
      fail("projects: " .. host .. ": " .. err)
    end
    return r.result or {}
  end, server
end

-- add_project is a folder browser in the palette. Each page lists the
-- folders inside one folder. Return on a repository adds it, and on any
-- other folder opens it. The first row adds the folder being browsed, so
-- a folder that is no repository can be a project too. Typing a path and
-- pressing Return on the last row jumps there, and a path that is a repository
-- is added. The palette filters only the rows it was given, so a path is not
-- completed while it is typed: a path that is no folder opens the nearest
-- folder above it, with the name that was not found as the filter. text is a
-- path typed before the browser opened, to start from. It returns the folder,
-- or nil and why the action ends: none when nothing was typed, the
-- palette's reason when the person gave up, or the reason to show.
local function add_project(call, text)
  local page, filter
  -- jump goes to a typed path. It returns the project when the path was a
  -- repository and is added now, or nil and why when there is nowhere to go.
  local function jump(typed_text)
    local typed = call("typed", { text = typed_text, dir = page and page.dir })
    if typed.why ~= nil then return nil, typed.why end
    if typed.repo then return call("add", { path = typed.dir }).path end
    page, filter = call("browse", { dir = typed.dir }), typed.rest
  end
  local function blank(typed_text) return expand(tostring(typed_text or "")) == "" end
  if text ~= nil then
    if blank(text) then return nil end
    local added, why = jump(text)
    if added ~= nil or why ~= nil then return added, why end
  else
    page = call("browse")
  end
  -- Each page waits for a pick, so a person ends the walk. The cap is for a
  -- picker that answers without one, such as a script or a broken palette.
  for _ = 1, 200 do
    local picked, why = rex.ui.pick{
      title = "Add project",
      placeholder = page.placeholder,
      value = filter,
      allow_other = true,
      items = page.rows,
    }
    filter = nil
    if picked == nil then return nil, why end
    if type(picked) == "table" then
      -- The person typed a path instead of choosing a row.
      if blank(picked.text) then return nil end
      local added, stopped = jump(picked.text)
      if added ~= nil or stopped ~= nil then return added, stopped end
    elseif picked == ADD_HERE then
      return call("add", { path = page.dir }).path
    elseif picked == UP then
      page = call("browse", { dir = page.parent })
    elseif page.repos and page.repos[picked] then
      return call("add", { path = picked }).path
    else
      page = call("browse", { dir = picked })
    end
  end
  return nil, "projects: too many steps"
end

-- remove_missing asks whether to take project, whose folder is missing, off
-- the list, and does so on Remove. Either way the action ends.
local function remove_missing(call, project)
  local answer, why = rex.ui.pick{
    title = basename(project) .. " is missing",
    items = {
      { id = "keep", title = "Keep", subtitle = "It stays on the list" },
      { id = "remove", title = "Remove from list", subtitle = "Take it off the list" },
    },
  }
  if answer == "remove" then call("forget", { project = project }) end
  if answer == nil then fail(why) end
  return nil
end

-- choose_project asks for a project, which may be one added on the spot. A
-- typed path opens the Add project browser there. cwd is the folder of the
-- terminal the action was run from, whose project is listed first. It
-- returns the folder, or nil when the person gave up; any other reason is
-- raised. A missing project is offered for removal instead.
local function choose_project(ctx, call, title, cwd)
  local items = call("projects", { cwd = cwd }).rows
  local project, why = rex.ui.pick{
    title = ctx.server and (title .. " on " .. ctx.server) or title,
    placeholder = "Project or path",
    allow_other = true,
    items = items,
  }
  if type(project) == "table" then
    project, why = add_project(call, project.text)
  elseif project == ADD_PROJECT then
    project, why = add_project(call)
  elseif project ~= nil then
    for _, row in ipairs(items) do
      if row.id == project and row.detail == "missing" then return remove_missing(call, project) end
    end
  end
  if project == nil then fail(why) end
  return project
end

-- typed_or_picked returns the answer of a list that also takes typed text,
-- as text either way.
local function typed_or_picked(answer)
  if type(answer) == "table" then return trim(tostring(answer.text or "")) end
  return answer
end

-- terminal_dir returns the folder of the terminal the action was run from,
-- or nil when there is none to ask.
local function terminal_dir(ctx, server)
  local session, block = ctx.session_id, ctx.block_id
  if session == nil then return nil end
  if block == nil then
    -- An action run for a session on another host is not always told the
    -- focused block, so look it up.
    local view = server.call("session.view", { session_id = session })
    for _, window in ipairs(view and view.windows or {}) do
      if window.window_id == view.active_window_id then block = window.focused_block_id end
    end
    if block == nil then return nil end
  end
  local p = server.call("block.method", { session_id = session, block_id = block, method = "process" })
  if type(p) ~= "table" then return nil end
  -- foreground is the shell at its prompt, or what it runs. child is what the
  -- terminal started, which on macOS is login and stays where it started.
  return p.foreground and p.foreground.cwd or p.child and p.child.cwd or nil
end

-- session_exists says whether the server still has the session.
local function session_exists(server, id)
  local list = server.call("session.list")
  for _, s in ipairs(list and list.sessions or {}) do
    if s.session_id == id then return true end
  end
  return false
end

-- shaped calls the label or layout setting, by name, with its own copy of
-- t, and answers what it returns when fits says it may be used. On an error
-- or another answer it warns and answers nil, and the action goes on.
local function shaped(name, t, fits)
  local f = config[name]
  if f == nil then return nil end
  local copy = {}
  for k, v in pairs(t) do copy[k] = v end
  local ok, v = pcall(f, copy)
  if ok and fits(v) then return v end
  local what = ok and "answered " .. shown(v) or "failed: " .. (type(v) == "string" and v or shown(v))
  rex.log("warn", one_line("projects: the " .. name .. " function " .. what))
  return nil
end

local function is_label(v) return type(v) == "string" end
-- session.create needs a window, so an empty table is no layout.
local function is_layout(v) return type(v) == "table" and v[1] ~= nil end

-- session_for goes to the session of the checkout that r, the answer of an
-- open op, names. That is the session remembered for the checkout, while it
-- still exists. Else it is the session the action was run from, when r says
-- it may be adopted, and that session gets the checkout's label. Else it is
-- a new one. The id of an adopted or new session is remembered, in place of
-- one that is gone. The label setting gives an adopted or new session its
-- label, and the layout setting gives a new one its windows.
local function session_for(ctx, call, server, r)
  local id = r.session
  if id == nil or not session_exists(server, id) then
    local adopting = r.adopt and ctx.session_id ~= nil
    local t = { project = r.project, branch = r.branch, dir = r.dir, host = ctx.server,
      pr = r.pr, shell = r.shell, label = r.label }
    local label = shaped("label", t, is_label) or r.label
    if adopting then
      id = ctx.session_id
      local renamed, err = server.call("session.set_label", { session_id = id, label = label })
      if renamed == nil then
        rex.log("warn", "projects: cannot rename the session: " .. tostring(err))
      end
    else
      -- A window in the API is a tab in the app.
      local shell_tab = { {
        window_label = "shell",
        layout = rex.layout.block{
          flavor = "com.superlogical.terminal.shell",
          -- The app's Startup Command setting only reaches the terminals
          -- the app makes itself, and a script cannot read it.
          options = { cwd = r.dir, shell = r.shell },
        },
      } }
      local windows = shaped("layout", t, is_layout)
      local session, failed = server.call("session.create", { label = label, initial_windows = windows or shell_tab })
      if session == nil and windows ~= nil then
        rex.log("warn", "projects: the server refused the session with the layout function's windows: " ..
          one_line(failed) .. "; trying one shell tab")
        session, failed = server.call("session.create", { label = label, initial_windows = shell_tab })
      end
      if session == nil then fail("projects: " .. tostring(failed)) end
      id = session.session_id
    end
    call("keep", { dir = r.dir, session = id, created = not adopting })
  end
  -- Neither finding nor creating a session shows it. Ask the app to.
  --
  -- Not for a session on another host: the app looks for the session of
  -- session.select only on its own server and answers "was not found on this
  -- server". The session is ready there; go to it by hand. Remove this check
  -- once the app is fixed:
  -- https://discord.com/channels/1546797889009881158/1564771883998650438
  if ctx.server ~= nil then return end
  rex.client.queue("session.select", { session_id = id })
end

-- close_session is the one close path for the session of a checkout's
-- record, which the backend has forgotten by now. It ends the
-- session, and what runs in it, only when rex-projects created it and it is
-- still there; an adopted session stays open. A call on a session other
-- than the action's own fails until the caller attaches to it.
local function close_session(server, record)
  if not record.created then return end
  local id = record.session
  if not session_exists(server, id) then return end
  server.call("session.attach", { session_id = id })
  local closed, err = server.call("session.destroy", { session_id = id })
  if closed == nil then
    rex.log("warn", "projects: cannot close the worktree's session: " .. tostring(err))
  end
end

-- pick_branch asks for the branch in project: a row of rows, or a typed
-- name, and for a new branch, what it starts from. It answers the name as
-- git will get it and the base, or nil, nil and why the action ends there;
-- a nil why ends it quietly.
local function pick_branch(call, project, rows, title, placeholder)
  local name, why = rex.ui.pick{
    title = title,
    placeholder = placeholder,
    allow_other = true,
    items = rows,
  }
  if name == nil then return nil, nil, why end
  name = typed_or_picked(name)
  if name == "" then return nil, nil, nil end

  local n = call("name", { project = project, name = name })
  if n.why ~= nil then return nil, nil, n.why end
  if n.rows == nil then return n.name, nil end
  local base
  base, why = rex.ui.pick{
    title = "Start " .. n.name .. " from",
    placeholder = "Base branch",
    allow_other = true,
    items = n.rows,
  }
  if base == nil then return nil, nil, why end
  base = typed_or_picked(base)
  if base == "" then return nil, nil, nil end
  return n.name, base
end

-- switch_run is the body of Switch Branch in Project…: it asks for a project
-- and a branch, switches the project's own folder to the branch, and goes
-- to the project's session.
local function switch_run(ctx)
  ctx = ctx or {}
  local call, server = connect(ctx)

  -- The folder of the terminal the action was run from: its project is
  -- listed first, and its session may become the checkout's.
  local cwd = terminal_dir(ctx, server)
  local project = choose_project(ctx, call, "Switch branch", cwd)
  if project == nil then return end

  -- A plain folder has no branches.
  local list = call("here_rows", { project = project })
  local name, base, why = nil, nil, nil
  if not list.plain then
    name, base, why = pick_branch(call, project, list.rows or {},
      "Switch branch in " .. basename(project), "Branch or new name")
    if name == nil then return fail(why) end
  end

  local r = call("switch_here", { project = project, name = name, base = base,
    from = ctx.session_id, cwd = cwd })
  if r.why ~= nil then return fail(r.why) end
  session_for(ctx, call, server, r)
end

-- worktree_run is the body of Open Worktree in Project…: it asks for a
-- project and a branch, makes the branch's worktree when it has none, and
-- goes to the worktree's session.
local function worktree_run(ctx)
  ctx = ctx or {}
  local call, server = connect(ctx)

  -- The folder of the terminal the action was run from: its project is
  -- listed first, and its session may become the checkout's.
  local cwd = terminal_dir(ctx, server)
  local project = choose_project(ctx, call, "Open worktree", cwd)
  if project == nil then return end

  -- A plain folder has no branches.
  local list = call("worktree_rows", { project = project })
  local name, base, why = nil, nil, nil
  if not list.plain then
    name, base, why = pick_branch(call, project, list.rows or {},
      "Open worktree in " .. basename(project), "Worktree, branch or new name")
    if name == nil then return fail(why) end
  end

  local r = call("open_worktree", { project = project, name = name, base = base,
    from = ctx.session_id, cwd = cwd })
  if r.why ~= nil then return fail(r.why) end
  session_for(ctx, call, server, r)
end

-- clean_up is the body of Clean Up Branch in Project…: it removes one
-- branch, with its worktree and that worktree's session.
local function clean_up(ctx)
  ctx = ctx or {}
  local call, server = connect(ctx)
  local project = choose_project(ctx, call, "Clean up branch", terminal_dir(ctx, server))
  if project == nil then return end

  local list = call("cleanup_rows", { project = project })
  if list.why ~= nil then return fail(list.why) end
  local branch, why = rex.ui.pick{
    title = "Clean up branch in " .. basename(project),
    placeholder = "Choose the branch to delete, with its worktree",
    items = list.rows or {},
  }
  if branch == nil then return fail(why) end

  local r = call("cleanup", { project = project, branch = branch })
  if r.why ~= nil then return fail(r.why) end
  -- wt failed, yet the worktree is gone, so its session goes too.
  if r.failed ~= nil then
    if r.record ~= nil then close_session(server, r.record) end
    return fail(r.failed)
  end

  -- wt keeps a branch with changes that the default branch lacks. Say so
  -- and offer to force.
  why = r.kept and r.kept.reason
  local record = r.record
  if r.kept and r.kept.force then
    local answer
    answer, why = rex.ui.pick{
      title = r.kept.reason,
      items = {
        { id = "keep", title = "Keep", subtitle = branch .. " and its commits stay" },
        { id = "force", title = "Force delete", subtitle = "wt remove -D " .. branch },
      },
    }
    if answer == "force" then
      local forced = call("cleanup", { project = project, branch = branch, force = true })
      why = forced.why or forced.failed or (forced.kept and forced.kept.reason)
      -- The worktree may have gone only now.
      record = record or forced.record
    end
  end

  -- Once the worktree is gone, its session goes too, whatever became of
  -- the branch, when rex-projects made it. It goes last, because this action
  -- may be running in it.
  if record ~= nil then close_session(server, record) end
  return fail(why)
end

-- add_run is the body of Add Project to List…: it adds a project and opens
-- no session.
local function add_run(ctx)
  local call = connect(ctx or {})
  local _, why = add_project(call)
  return fail(why)
end

-- remove_run is the body of Remove Project from List….
local function remove_run(ctx)
  local call = connect(ctx)
  local rows = call("saved").rows
  if rows == nil or #rows == 0 then return end
  local project, why = rex.ui.pick{
    title = "Remove project",
    placeholder = "Choose a project to forget (its folder stays)",
    items = rows,
  }
  if project == nil then return fail(why) end
  call("forget", { project = project })
end

-- review_run is the body of Review Pull Request…: it opens a pull request
-- in a worktree and goes to its session.
local function review_run(ctx)
  ctx = ctx or {}
  local call, server = connect(ctx)
  local cwd = terminal_dir(ctx, server)
  local project = choose_project(ctx, call, "Review pull request", cwd)
  if project == nil then return end

  local list = call("pulls", { project = project })
  if list.why ~= nil then return fail(list.why) end
  local picked, why = rex.ui.pick{
    title = "Review pull request in " .. basename(project),
    placeholder = "Pull request, number or link",
    allow_other = true,
    items = list.rows or {},
  }
  if picked == nil then return fail(why) end
  picked = typed_or_picked(picked)
  if picked == "" then return end

  local r = call("review", { project = project, pr = picked, from = ctx.session_id, cwd = cwd })
  if r.why ~= nil then return fail(r.why) end

  session_for(ctx, call, server, r)
end

rex.action{
  name = "switch_project_branch",
  title = "Switch Branch in Project…",
  description = "Choose a project and a branch, switch the project's folder to it, and go to the project's session",
  category = "Projects",
  keywords = "checkout branch repository folder session new project",
  run = switch_run,
}

rex.action{
  name = "open_project_worktree",
  title = "Open Worktree in Project…",
  description = "Choose a project and a branch, and go to the session of the branch's worktree, making both when needed",
  category = "Projects",
  keywords = "worktree branch repository folder session new project",
  run = worktree_run,
}

rex.action{
  name = "clean_up_project_branch",
  title = "Clean Up Branch in Project…",
  description = "Delete a finished branch, with its worktree and that worktree's session",
  category = "Projects",
  keywords = "delete remove branch worktree session finished merged",
  run = clean_up,
}

rex.action{
  name = "add_project",
  title = "Add Project to List…",
  description = "Choose a folder and add it to the list of projects",
  category = "Projects",
  keywords = "folder repository project list",
  run = add_run,
}

rex.action{
  name = "review_pull_request",
  title = "Review Pull Request…",
  description = "Choose a project and one of its open pull requests, and go to the session of its worktree, making both when needed",
  category = "Projects",
  keywords = "pull request pr review github worktree branch",
  run = review_run,
}

-- close_run closes the session rex-projects made for the checkout at
-- args.path, on this host, and forgets its record.
local function close_run(_, args)
  local path = args and args.path
  if type(path) ~= "string" or trim(path) == "" then return end
  local r = backend.forget_record{ path = path }
  if r.record then close_session(rex, r.record) end
end

rex.action{
  name = "remove_project",
  title = "Remove Project from List…",
  description = "Take a project off the list; its folder stays, and one a root finds stays hidden until added again",
  category = "Projects",
  keywords = "forget delete project list",
  run = remove_run,
}

rex.action{
  name = "close_project_session",
  title = "Projects: Close Checkout Session",
  description = "Close the session rex-projects made for the checkout at path; for wt's post-remove hook",
  category = "Internal",
  args = { path = "string?" },
  run = close_run,
}

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- bind_key moves the key of a key setting ("key" or "worktree_key") to key,
-- or removes it for false.
local function bind_key(setting, key)
  local action = key_actions[setting]
  -- Removing a binding works only while the file loads, which is when setup
  -- runs. pcall keeps a refusal from stopping the rest of init.lua.
  if bound_keys[setting] ~= nil then pcall(rex.unbind, bound_keys[setting]) end
  bound_keys[setting] = nil
  config[setting] = key
  if key then
    rex.bind(key, action)
    -- Keep the binding itself, which is the last one the action has now.
    -- Removing it leaves alone what the app, or the rest of init.lua, has on
    -- the same key; removing the key would take that too. A Rex that cannot
    -- list bindings gets the key.
    local ok, made = pcall(rex.bindings, { action = action })
    bound_keys[setting] = ok and type(made) == "table" and made[#made] or key
  end
end

local function is_string(v) return type(v) == "string" end
local function string_or_false(v) return v == false or type(v) == "string" end
local function function_or_false(v) return v == false or type(v) == "function" end
local function is_order(v) return v == "recent" or v == "name" end
local function string_list(v)
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  for i = 1, n do
    if type(v[i]) ~= "string" then return false end
  end
  return true
end

-- The options setup takes, in the order it applies them: each one's check,
-- and the words for what it wants. The keys go last.
local options = {
  { name = "worktrees", ok = is_string, wants = "a string" },
  { name = "roots", ok = string_list, wants = "a list of strings" },
  { name = "base", ok = string_or_false, wants = "a string or false" },
  { name = "project_order", ok = is_order, wants = '"recent" or "name"' },
  { name = "branch_order", ok = is_order, wants = '"recent" or "name"' },
  { name = "shell", ok = string_or_false, wants = "a string or false" },
  { name = "label", ok = function_or_false, wants = "a function or false" },
  { name = "layout", ok = function_or_false, wants = "a function or false" },
  { name = "state_file", ok = is_string, wants = "a string" },
  { name = "key", ok = string_or_false, wants = "a string or false" },
  { name = "worktree_key", ok = string_or_false, wants = "a string or false" },
}
local option_names = {}
for _, o in ipairs(options) do option_names[o.name] = true end

-- M.setup changes the settings it is given and leaves the rest as they were.
-- An unknown name, or a value that fails its check, is warned about and
-- changes nothing; false unsets the settings that allow it.
function M.setup(opts)
  if opts == nil then return M end
  if type(opts) ~= "table" then
    rex.log("warn", "projects: setup takes a table, not " .. shown(opts))
    return M
  end
  for name in pairs(opts) do
    if not option_names[name] then
      local plain = type(name) == "string" and name:match("^[%w_]+$")
      rex.log("warn", "projects: setup has no option " .. (plain and name or shown(name)))
    end
  end
  for _, o in ipairs(options) do
    local v = opts[o.name]
    if v ~= nil and not o.ok(v) then
      rex.log("warn", "projects: " .. o.name .. " must be " .. o.wants .. ", not " .. shown(v))
    elseif v ~= nil then
      if key_actions[o.name] then
        bind_key(o.name, v)
      else
        config[o.name] = v or nil
        if o.name == "state_file" then state = nil end
      end
    end
  end
  return M
end

bind_key("key", config.key)
bind_key("worktree_key", config.worktree_key)

-- Pure helpers, for the tests in test/.
M._internal = {
  expand = expand, short = short, basename = basename,
  load_state = load_state, save_state = save_state, worktrees = worktrees,
  checkouts = checkouts, here_rows = here_rows, worktree_rows = worktree_rows,
  cleanup_rows = cleanup_rows,
  base_rows = base_rows,
  project_rows = project_rows,
  subfolders = subfolders,
  parent_of = parent_of, is_folder = is_folder, reason = reason, fail = fail,
  wt_reason = wt_reason, toml = toml,
  switch_run = switch_run, worktree_run = worktree_run,
  clean_up = clean_up, add_run = add_run, remove_run = remove_run,
  review_run = review_run, pr_number = pr_number, owner_repo = owner_repo,
  backend = backend, config = config,
  tool_opts = tool_opts,
  reset = function() state = nil end,
  reset_login = function() login_cache = nil end,
}

return M
