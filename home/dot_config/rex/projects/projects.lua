-- rex-projects: pick a project, then a branch, and land in its session.
--
-- Two actions share one flow. Each asks for a project from a list you keep,
-- then lists the project's branches, where you choose a row or type a name:
--
--   Switch Branch in Project…  (alt+cmd+n) works in the project's own folder.
--     It switches the branch there and goes to the project's session.
--   Open Worktree in Project…  (ctrl+alt+cmd+n) works in a worktree, a
--     second checkout of the repository in its own folder. It makes the
--     worktree when the branch has none, and goes to the worktree's session.
--
-- A name that matches no branch makes a new one, after a second list asks
-- what it starts from. Each checkout has one session, and the script
-- remembers which, so choosing a checkout again goes back to its session
-- instead of opening another. Clean Up Branch in Project… deletes a finished
-- branch, with its worktree and that worktree's session.
--
-- The projects are the ones on the machine of the focused session. For a
-- session on a remote host, the pickers still run here, and the folder and
-- git work runs on that host, which needs this file in its init.lua too.
--
-- Install: put this file next to init.lua and add to init.lua
--
--     require("projects")
--
-- Optional settings, before or after the require:
--
--     require("projects").setup{
--       key           = "alt+cmd+n",        -- Switch Branch; false binds nothing
--       worktree_key  = "ctrl+alt+cmd+n",   -- Open Worktree; false binds nothing
--       base          = "main",             -- what a new branch starts from;
--                                           -- unset, the remote's default branch
--       shell         = "fish",             -- the shell of a new session
--       worktrees     = "~/.rex/worktrees", -- where new worktrees are made
--       roots         = { "~/src" },        -- folders whose repositories are
--                                           -- listed without being added
--       project_order = "recent",           -- project picker: "recent" or "name"
--       branch_order  = "recent",           -- branch lists: "recent" or "name"
--     }
--
-- Written for Lua 5.1 (what Rex embeds) and for init.lua, which runs
-- unsandboxed on the server. Without io, the project list is kept only
-- until the server restarts, and the script says so in the log.

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
  -- means the remote's default branch, else "main"
  shell = nil, -- nil means the account's default shell
  worktrees = nil, -- nil means <home>/.rex/worktrees
  roots = {},
  project_order = "recent", -- the project picker's order: "recent" or "name"
  branch_order = "recent", -- the branch lists' order: "recent" (newest commit) or "name"
  state_file = nil, -- nil means <config dir>/rex/projects.json
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

-- The first character of package.config is the directory separator, and it
-- is a backslash only on Windows.
local is_windows = (package and package.config or "/"):sub(1, 1) == "\\"

-- env returns an environment variable, or nil when it is unset or empty, or
-- when this script has no os library.
local function env(name)
  if os == nil or os.getenv == nil then return nil end
  local value = os.getenv(name)
  if value == nil or value == "" then return nil end
  return value
end

local home = env("HOME") or env("USERPROFILE") or ""

-- slashes writes every separator as "/", which git and Windows both take.
local function slashes(path)
  return (path:gsub("\\", "/"))
end

-- expand writes a leading ~ as the home folder and trims blanks and quotes
-- that a pasted path carries.
local function expand(path)
  path = path:gsub("^%s+", ""):gsub("%s+$", "")
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  path = slashes(path)
  if path == "~" then return slashes(home) end
  if path:sub(1, 2) == "~/" then return slashes(home) .. path:sub(2) end
  return path
end

-- short writes the home folder at the start of path as ~.
local function short(path)
  local h = slashes(home)
  if h ~= "" and path:sub(1, #h + 1) == h .. "/" then
    return "~" .. path:sub(#h + 1)
  end
  return path
end

-- basename returns the last component of a slash-separated path.
local function basename(path)
  return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

-- trim removes blanks from both ends of s.
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- output runs a command and returns what it printed, or nil when it failed
-- or did not run. Its arguments are rex.exec's, passed on as they came.
local function output(...)
  local r = rex.exec(...)
  if r == nil or not r.ok then return nil end
  return r.stdout
end

-- worktrees_dir is the folder that new worktrees are made in, as
-- <dir>/<project>/<branch>.
local function worktrees_dir()
  if config.worktrees then return expand(config.worktrees) end
  local from_env = env("REX_WORKTREES")
  if from_env then return expand(from_env) end
  return slashes(home) .. "/.rex/worktrees"
end

-- real returns dir as the system spells it, with every symbolic link
-- followed, or dir itself when that cannot be found out.
local function real(dir)
  if is_windows then return dir end
  local out = output({ "pwd", "-P" }, { cwd = dir })
  if out == nil then return dir end
  out = trim(out)
  return out ~= "" and out or dir
end

---------------------------------------------------------------------------
-- State: the project list and each checkout's session
---------------------------------------------------------------------------

-- state is { projects = { path, ... }, sessions = { [folder] = session id },
-- recent = { path, ... } }. sessions names the session of each checkout by
-- the checkout's folder: a project's own folder, or the folder of one of its
-- worktrees. recent holds the projects that were opened, the last one first.
local state = nil

-- state_path returns where the state is kept, or nil when there is nowhere.
local function state_path()
  if config.state_file then return expand(config.state_file) end
  local base
  if is_windows then
    base = env("APPDATA")
  else
    base = env("XDG_CONFIG_HOME") or (home ~= "" and (home .. "/.config") or nil)
  end
  if base == nil then return nil end
  return slashes(base) .. "/rex/projects.json"
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
  state = { projects = {}, sessions = {}, recent = {} }
  local path = state_path()
  if io == nil or io.open == nil or path == nil then return state end
  local file = io.open(path, "r")
  if file == nil then return state end
  local text = file:read("*a")
  file:close()
  local ok, decoded = pcall(rex.json.decode, text)
  if ok and type(decoded) == "table" then
    -- Read each member by hand: another version of this file may hold more.
    state.projects = strings(decoded.projects)
    state.recent = strings(decoded.recent)
    if type(decoded.sessions) == "table" then
      for k, v in pairs(decoded.sessions) do
        if type(k) == "string" and type(v) == "string" then state.sessions[k] = v end
      end
    end
  end
  return state
end

-- save_state writes the state. It returns nothing and never raises: failing
-- to remember is not worth stopping a session for.
local function save_state()
  local path = state_path()
  if io == nil or io.open == nil or path == nil then
    if not warned_memory_only then
      warned_memory_only = true
      rex.log("warn", "projects: no place to save the project list; it lasts until the server restarts")
    end
    return
  end
  -- Make the folder first. mkdir -p exists on every Unix; Windows mkdir
  -- makes parents by itself and fails when the folder exists, which is fine.
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    if is_windows then
      rex.exec({ "cmd", "/c", "mkdir", (dir:gsub("/", "\\")) })
    else
      rex.exec({ "mkdir", "-p", dir })
    end
  end
  local file, err = io.open(path, "w")
  if file == nil then
    rex.log("warn", "projects: cannot save " .. path .. ": " .. tostring(err))
    return
  end
  file:write(rex.json.encode({ projects = state.projects, sessions = state.sessions, recent = state.recent }))
  file:close()
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

-- git runs git in dir and returns what it printed, or nil and git's message.
-- Arguments go as a list, never through a shell, so no quoting is needed.
local function git(dir, ...)
  local r, err = rex.exec({ "git", "-C", dir, ... })
  if r == nil then return nil, tostring(err or "git did not run") end
  if not r.ok then
    local message = trim(r.stderr)
    if message == "" then message = "git exited with status " .. tostring(r.code) end
    return nil, reason(message)
  end
  return r.stdout
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
  local out = git(dir, "rev-parse", "--show-toplevel")
  if out == nil then return nil end
  out = trim(out)
  return out ~= "" and slashes(out) or nil
end

-- current_branch returns the branch checked out in dir, or nil when HEAD is
-- detached.
local function current_branch(dir)
  local out = git(dir, "symbolic-ref", "--short", "-q", "HEAD")
  if out == nil then return nil end
  out = trim(out)
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
        path = slashes(path),
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

-- valid_branch_name says whether git accepts name as a branch name. When it
-- does not, the second result is git's message.
local function valid_branch_name(project, name)
  local out, err = git(project, "check-ref-format", "--branch", name)
  return out ~= nil, err
end

---------------------------------------------------------------------------
-- Projects
---------------------------------------------------------------------------

-- windows_folders lists the names of the folders directly inside dir, on
-- Windows, where dir /b /ad lists folder names only.
local function windows_folders(dir)
  local names = {}
  local out = output({ "cmd", "/c", "dir", "/b", "/ad", (dir:gsub("/", "\\")) })
  if out == nil then return names end
  for name in out:gmatch("[^\r\n]+") do names[#names + 1] = name end
  return names
end

-- repos_in lists the repositories directly inside dir, as paths, on Unix.
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
  local roots = config.roots
  local from_env = env("REX_PROJECTS")
  if from_env then
    roots = { from_env }
    for _, r in ipairs(config.roots) do roots[#roots + 1] = r end
  end
  for _, root in ipairs(roots) do
    root = expand(root)
    if is_windows then
      for _, name in ipairs(windows_folders(root)) do
        local path = root .. "/" .. name
        if is_repo_root(path) then found[#found + 1] = path end
      end
    else
      for _, path in ipairs(repos_in(root)) do found[#found + 1] = path end
    end
  end
  return found
end

-- The ids of the rows that are not a folder. They travel as JSON between
-- servers, so they hold no NUL byte; a colon keeps them apart from any real
-- path, which starts with "/" or a drive letter.
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

-- project_row returns the picker row of the project at path.
local function project_row(path)
  return { id = path, title = basename(path), subtitle = short(path), icon = "folder" }
end

-- containing returns the project of paths that holds the folder cwd, or nil.
-- A worktree belongs to the project of its main checkout, which is the first
-- checkout git lists. A plain folder goes by its path, and the deepest
-- project that holds cwd wins.
local function containing(paths, cwd)
  if cwd == nil or cwd == "" then return nil end
  cwd = slashes(cwd)
  local trees = worktrees(cwd)
  local main = trees and trees[1] and trees[1].path or nil
  -- The terminal and the list may spell a folder through a symbolic link.
  -- Only a project named like the main checkout is worth asking about.
  local real_cwd = real(cwd)
  local best = nil
  for _, p in ipairs(paths) do
    if main ~= nil and (p == main or (basename(p) == basename(main) and real(p) == main)) then
      return p
    end
    local function holds(dir) return dir == p or dir:sub(1, #p + 1) == p .. "/" end
    if (holds(cwd) or holds(real_cwd)) and (best == nil or #p > #best) then best = p end
  end
  return best
end

-- project_rows returns the rows of the project picker: the added projects
-- and the scanned ones, then the row that adds a project. The project that
-- holds cwd, the folder of the terminal the action was run from, goes
-- first. Then, with project_order "recent", the most recently used go first
-- and the rest by name; with "name" all go by name.
local function project_rows(cwd)
  local s = load_state()
  local seen, paths = {}, {}
  for _, p in ipairs(s.projects) do
    if not seen[p] then seen[p] = true; paths[#paths + 1] = p end
  end
  for _, p in ipairs(scan()) do
    if not seen[p] then seen[p] = true; paths[#paths + 1] = p end
  end
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
  local rows = {}
  for _, p in ipairs(paths) do rows[#rows + 1] = project_row(p) end
  rows[#rows + 1] = { id = ADD_PROJECT, title = "Add project…", subtitle = "Choose a folder", icon = "plus" }
  return rows
end

-- is_folder says whether path is a folder on this machine.
local function is_folder(path)
  if is_windows then
    -- A folder holds the NUL device on Windows; a file does not.
    local native = path:gsub("/", "\\")
    local out = output({ "cmd", "/c", "if", "exist", native .. "\\NUL", "echo", "yes" })
    return out ~= nil and out:find("yes", 1, true) ~= nil
  end
  return output({ "test", "-d", path }) ~= nil
end

-- subfolders lists the folders directly inside dir as { path = ..., repo =
-- boolean }, sorted by name, hidden folders left out. It returns an empty list
-- for a folder it cannot read.
local function subfolders(dir)
  local list = {}
  if is_windows then
    -- Repositories are not marked: one git call for each folder would be
    -- slow, and Return then opens the folder, from where "Add" is one row
    -- away.
    local base = dir:gsub("/+$", "")
    for _, name in ipairs(windows_folders(dir)) do
      if name:sub(1, 1) ~= "." then
        list[#list + 1] = { path = base .. "/" .. name, repo = false }
      end
    end
  else
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
  end
  table.sort(list, function(a, b) return basename(a.path):lower() < basename(b.path):lower() end)
  return list
end

-- parent_of returns the folder above dir, or nil at the top.
local function parent_of(dir)
  local parent = dir:match("^(.*)/[^/]+/?$")
  if parent == nil or parent == "" then
    -- "/x" has the parent "/"; "C:/x" has "C:/".
    if dir:match("^/[^/]+/?$") then return "/" end
    return nil
  end
  if parent:match("^%a:$") then return parent .. "/" end
  return parent
end

-- save_project adds path to the list, once, and returns it.
local function save_project(path)
  local s = load_state()
  for _, p in ipairs(s.projects) do
    if p == path then return path end
  end
  s.projects[#s.projects + 1] = path
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
  local c = { current = current_branch(project), others = {}, taken = {} }
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

-- branch_rows returns the one list of branches that a mode shows.
--   "here"      the main checkout's branch, then every other regular branch,
--               then the remote branches
--   "worktree"  the worktrees, then the regular branches, then the remote ones
--   "cleanup"   the worktrees and the regular branches
-- A regular branch is a local one that no worktree holds. Only "here" lists
-- the main checkout's branch: it cannot get a worktree or be deleted. A
-- remote branch is listed while no local branch has its name, once for each
-- remote that has it.
local function branch_rows(project, mode, c)
  local rows, add = row_list()
  if mode == "here" then
    if c.current then add(c.current, "current branch") else add("HEAD", "detached") end
  else
    for _, tree in ipairs(c.others) do
      -- A worktree whose folder is gone can only be cleaned up.
      if tree.branch and (mode == "cleanup" or not tree.prunable) then
        add(tree.branch, short(tree.path), "folder")
      end
    end
  end
  local locals = {}
  for _, name in ipairs(local_branches(project)) do
    locals[name] = true
    if name ~= c.current and not c.taken[name] then add(name) end
  end
  if mode ~= "cleanup" then
    for _, remote in ipairs(remote_branches(project)) do
      if not locals[remote.branch] then add(remote.name) end
    end
  end
  return rows
end

-- remote_head returns the branch that git recorded as the default branch of
-- remote, such as "main", or nil. git clone records it in
-- refs/remotes/<remote>/HEAD; a remote added by hand has none until
-- git remote set-head runs.
local function remote_head(project, remote)
  local out = git(project, "symbolic-ref", "--quiet", "refs/remotes/" .. remote .. "/HEAD")
  if out == nil then return nil end
  local prefix = "refs/remotes/" .. remote .. "/"
  out = trim(out)
  if out:sub(1, #prefix) ~= prefix or #out == #prefix then return nil end
  return out:sub(#prefix + 1)
end

-- default_base returns the name of what a new branch starts from by
-- default: the base setting, else the default branch of origin, else of the
-- first other remote that has one recorded, else "main". It reads only what
-- is on disk, so it costs no network call.
local function default_base(project)
  if config.base then return config.base end
  local remotes = {}
  local out = git(project, "remote")
  for line in (out or ""):gmatch("[^\r\n]+") do
    if line == "origin" then table.insert(remotes, 1, line) else remotes[#remotes + 1] = line end
  end
  for _, remote in ipairs(remotes) do
    local head = remote_head(project, remote)
    if head ~= nil then return head end
  end
  return "main"
end

-- default_remote_base returns the remote branch of the default base, as
-- { name = "origin/main", remote = "origin", branch = "main" }, or nil when
-- it has none. That is the branch the local one follows, else the branch of
-- that name on origin, else on the first remote that has it. Only one that
-- was fetched before counts, so that the row names something.
local function default_remote_base(project)
  local base = default_base(project)
  local remote, branch = nil, nil
  if has_ref(project, "refs/heads/" .. base) then
    local r = trim(git(project, "config", "--get", "branch." .. base .. ".remote") or "")
    local m = trim(git(project, "config", "--get", "branch." .. base .. ".merge") or "")
    -- A remote of "." is the repository itself.
    if r ~= "" and r ~= "." and m:find("^refs/heads/") then
      remote, branch = r, m:sub(#"refs/heads/" + 1)
    end
  end
  if remote == nil then
    for _, r in ipairs(remote_branches(project)) do
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
    -- Leave the default out where it names nothing, such as "main" in a
    -- repository with no remote whose first branch is "master", so that
    -- Return on the first row always works. The default may be any commit,
    -- so rev-parse reads it.
    local base = default_base(project)
    if git(project, "rev-parse", "--verify", "--quiet", base .. "^{commit}") ~= nil then
      add(base, "default")
    end
  end
  if c.current then add(c.current, "current branch") else add("HEAD", "detached") end
  for _, name in ipairs(local_branches(project)) do add(name) end
  for _, remote in ipairs(remote_branches(project)) do add(remote.name) end
  return rows
end

-- add_worktree makes a worktree of project for branch, in
-- <worktrees>/<project>/<branch>. Without base, the branch exists already.
-- With base, the branch is new and starts there, and track ("--track",
-- "--no-track", or nil for what git does by itself) says whether it follows
-- base. It returns the folder as git spells it, or nil and git's message.
local function add_worktree(project, branch, base, track)
  -- A branch name may hold slashes; a folder name may not.
  local folder = branch:gsub("[/\\:]", "-")
  local dir = worktrees_dir() .. "/" .. basename(project) .. "/" .. folder
  local args = { "worktree", "add" }
  if base ~= nil then
    if track ~= nil then args[#args + 1] = track end
    args[#args + 1] = "-b"
    args[#args + 1] = branch
  end
  args[#args + 1] = dir
  args[#args + 1] = base or branch
  local _, err = git(project, unpack(args))
  if err ~= nil then return nil, err end
  -- Git may spell the folder differently from the path made here (a symlink
  -- such as /tmp), and its list of worktrees gives git's spelling next time.
  for _, tree in ipairs(worktrees(project) or {}) do
    if tree.branch == branch then return tree.path end
  end
  return dir
end

-- switch_branch checks branch out in the project's own folder. base and
-- track mean what they do in add_worktree. It returns true, or nil and git's
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

-- inside says whether the folder cwd is in the checkout at dir. In a
-- repository both must have the same top folder, which keeps a worktree made
-- inside another checkout apart from it. A plain folder goes by its path.
local function inside(cwd, dir, repo)
  cwd = slashes(cwd)
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
-- already the session of another checkout.
local function landing(dir, label, a, repo)
  local sessions = load_state().sessions
  local adopt = a.from ~= nil and a.cwd ~= nil and inside(a.cwd, dir, repo)
  if adopt then
    for folder, id in pairs(sessions) do
      if id == a.from and folder ~= dir then adopt = false end
    end
  end
  return { dir = dir, label = label, session = sessions[dir], adopt = adopt, shell = config.shell }
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
-- booleans and tables. An op that git refuses answers { why = git's message }
-- instead of raising, so that the message arrives as git wrote it.
local backend = {}

-- start_dir is the folder the Add project browser opens in: the first root,
-- else REX_PROJECTS, else the home folder.
local function start_dir()
  local first = config.roots[1] or env("REX_PROJECTS")
  local dir = first and expand(first) or slashes(home)
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
  if path == "" then return { why = "cancelled" } end
  if path:sub(1, 1) ~= "/" and not path:match("^%a:/") then
    local base = a.dir or start_dir()
    path = (base == "/" and "" or base:gsub("/+$", "")) .. "/" .. path
  end
  if #path > 1 and not path:match("^%a:/$") then path = path:gsub("/+$", "") end
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

-- branches returns the rows of the branch list that a.mode shows for
-- a.project: "here", "worktree" or "cleanup". A folder with no repository
-- has no branches. The two modes that open a session answer plain = true for
-- it, and clean-up, which has nothing to do there, answers why with what git
-- said.
function backend.branches(a)
  local c, unreadable = checkouts(a.project)
  if c == nil then
    if a.mode == "cleanup" then return { why = unreadable } end
    return { plain = true }
  end
  local rows = branch_rows(a.project, a.mode, c)
  if a.mode == "cleanup" and #rows == 0 then
    return { why = basename(a.project) .. " has no branch to clean up" }
  end
  return { rows = rows }
end

-- open makes the checkout for the branch a.name ready and says where it is.
-- a.mode is "here", which switches the branch in the project's own folder,
-- or "worktree", which gives the branch a worktree. The name is read as a
-- local branch, then as a remote one ("origin/x", which becomes a local
-- branch "x" that tracks it), and else as a new branch, which starts from
-- a.base. a.from is the session the action was run from and a.cwd the folder
-- of its terminal.
--
-- It answers one of
--   { dir, label, session, adopt }  where to work; see landing
--   { name, bases }                 the name is new and has no base yet:
--                                   the name as git will get it, and the
--                                   rows to choose a base from
--   { why }                         git refused, and nothing further changed
--
-- A project whose checkout is ready goes first on the recent list.
local open_checkout
function backend.open(a)
  local r = open_checkout(a)
  if r.dir ~= nil then mark_used(a.project) end
  return r
end

function open_checkout(a)
  local project = a.project
  local title = basename(project)
  local c = checkouts(project)
  -- A plain folder is one place to work, whatever the mode.
  if c == nil then return landing(project, title, a, false) end

  -- No branch name holds a space, so a typed one means a dash.
  local name = trim(a.name or "")
  name = name:gsub("%s+", "-")
  if name == "" then return { why = "no branch was named" } end

  local worktree = a.mode == "worktree"
  if worktree then
    local tree = c.taken[name]
    if tree ~= nil and not tree.prunable then
      return landing(tree.path, title .. " · " .. name, a, true)
    end
  elseif name == (c.current or "HEAD") then
    return landing(project, title, a, true)
  end

  -- What git is asked for: an existing branch as it is (no base), or a new
  -- one from a base.
  local branch, base, track = name, nil, nil
  if not has_ref(project, "refs/heads/" .. name) then
    local remote = nil
    for _, r in ipairs(remote_branches(project)) do
      if r.name == name then remote = r; break end
    end
    if remote ~= nil then
      branch, base, track = remote.branch, name, "--track"
    else
      local valid, err = valid_branch_name(project, name)
      if not valid then return { why = err } end
      base = trim(a.base or "")
      if base == "" then return { name = name, bases = base_rows(project, c) } end
      -- Git would read a base that starts with a dash as an option.
      if base:sub(1, 1) == "-" then return { why = "not a branch or a commit: " .. base } end
      -- The default base starts from what its remote has now. Every other
      -- base is taken as it is here, unpushed commits and all.
      local fetched = default_remote_base(project)
      if fetched ~= nil and base == fetched.name then
        local _, err = git(project, "fetch", "--quiet", fetched.remote, fetched.branch)
        if err ~= nil then return { why = err } end
      end
      -- A new branch does not follow the remote branch it starts from,
      -- however that branch was written: origin/x, remotes/origin/x.
      local full = git(project, "rev-parse", "--symbolic-full-name", base)
      if full ~= nil and full:find("^refs/remotes/") then track = "--no-track" end
    end
  end

  if worktree then
    local dir, err = add_worktree(project, branch, base, track)
    if dir == nil then return { why = err } end
    return landing(dir, title .. " · " .. branch, a, true)
  end
  local ok, err = switch_branch(project, branch, base, track)
  if not ok then return { why = err } end
  return landing(project, title, a, true)
end

-- keep remembers a.session as the session of the checkout in a.dir.
function backend.keep(a)
  load_state().sessions[a.dir] = a.session
  save_state()
  return {}
end

-- cleanup removes the branch a.branch of a.project: first its worktree, when
-- it has one, then the branch with git branch -d. A worktree with changed or
-- untracked files is refused and nothing changes; ignored files do not count.
-- With a.force it only deletes the branch, with git branch -D.
--
-- It answers
--   { why }               refused, by this script or by git
--   { session, refused }  session is the one remembered for the worktree
--                         that was removed, for the caller to close; refused
--                         is git's reason when it kept the branch
function backend.cleanup(a)
  local project, branch = a.project, a.branch
  local c, unreadable = checkouts(project)
  if c == nil then return { why = unreadable } end
  if a.force then
    local _, err = git(project, "branch", "-D", branch)
    if err ~= nil then return { why = err } end
    return {}
  end

  local session = nil
  local tree = c.taken[branch]
  if tree ~= nil then
    -- Git refuses such a worktree too, but names the folder; this names the
    -- branch. A worktree whose folder is gone has no files to lose.
    -- Untracked files are asked for by name: status.showUntrackedFiles=no
    -- would hide them here, and git worktree remove would then delete them.
    if not tree.prunable then
      local status, err = git(tree.path, "status", "--porcelain", "--untracked-files=normal")
      if status == nil then return { why = err } end
      if trim(status) ~= "" then
        return { why = "Nothing was deleted: the worktree of " .. branch
          .. " has uncommitted changes. Commit or discard them, then clean up again." }
      end
    end
    local _, err = git(project, "worktree", "remove", tree.path)
    if err ~= nil then return { why = err } end
    local s = load_state()
    session = s.sessions[tree.path]
    if session ~= nil then
      s.sessions[tree.path] = nil
      save_state()
    end
  end

  local _, err = git(project, "branch", "-d", branch)
  if err ~= nil then return { session = session, refused = err } end
  return { session = session }
end

-- saved returns the rows of the projects on the list, for Remove Project.
function backend.saved()
  local rows = {}
  for _, p in ipairs(load_state().projects) do rows[#rows + 1] = project_row(p) end
  return { rows = rows }
end

-- forget takes project off the list.
function backend.forget(a)
  local s = load_state()
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

-- The app cannot hide an action, so this one sits in a category of its own,
-- away from the ones a person runs.
rex.action{
  name = "projects_backend",
  title = "Projects: Backend",
  description = "Used by the Projects actions to read folders and run git where the projects are",
  category = "Internal",
  args = { op = "string?", args = "object?" },
  run = function(_, args)
    -- Run from the palette, it has no op and does nothing.
    if args == nil or args.op == nil then return end
    local op = backend[args.op]
    if op == nil then error("projects_backend: unknown op " .. tostring(args.op), 0) end
    return op(args.args or {})
  end,
}

---------------------------------------------------------------------------
-- The actions
---------------------------------------------------------------------------

-- fail raises a one-line error that names the script.
local function fail(message)
  error("projects: " .. tostring(message), 0)
end

-- stop ends an action whose question got no answer. A person who cancels is
-- not worth a log line. Any other reason is, because the palette that would
-- show it is what failed.
local function stop(why)
  if why ~= nil and why ~= "cancelled" then
    rex.log("warn", "projects: " .. tostring(why))
  end
end

-- refuse ends the action with a message for the person, such as git's own
-- words for what it would not do. The app shows an action's error, so the
-- message is raised as one, on one line.
local function refuse(text)
  error((trim(tostring(text)):gsub("%s+", " ")), 0)
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
      args = { op = op, args = args or {} },
    })
    if r == nil then
      err = tostring(err)
      if err:find("not.found") then
        err = err .. " (is projects.lua in init.lua on " .. host .. "?)"
      end
      fail(host .. ": " .. err)
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
-- or nil and why ("cancelled" when the person gave up, or was told that the
-- typed path is no folder).
local function add_project(call, text)
  local page, filter
  -- jump goes to a typed path. It returns the project when the path was a
  -- repository and is added now, or nil and why when there is nowhere to go.
  local function jump(typed_text)
    local typed = call("typed", { text = typed_text, dir = page and page.dir })
    if typed.why ~= nil then
      if typed.why ~= "cancelled" then refuse(typed.why) end
      return nil, "cancelled"
    end
    if typed.repo then return call("add", { path = typed.dir }).path end
    page, filter = call("browse", { dir = typed.dir }), typed.rest
  end
  if text ~= nil then
    local added, why = jump(text)
    if added ~= nil or why ~= nil then return added, why end
  else
    page = call("browse")
  end
  -- A folder tree is finite, but a typed path can loop; the cap keeps a
  -- script from asking forever.
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
  return nil, "too many steps"
end

-- choose_project asks for a project, which may be one added on the spot. A
-- typed path opens the Add project browser there. cwd is the folder of the
-- terminal the action was run from, whose project is listed first. It
-- returns the folder, or nil when the person gave up.
local function choose_project(ctx, call, title, cwd)
  local project, why = rex.ui.pick{
    title = ctx.server and (title .. " on " .. ctx.server) or title,
    placeholder = "Project or path",
    allow_other = true,
    items = call("projects", { cwd = cwd }).rows,
  }
  if type(project) == "table" then
    project, why = add_project(call, project.text)
  elseif project == ADD_PROJECT then
    project, why = add_project(call)
  end
  if project == nil then stop(why) end
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

-- session_for goes to the session of the checkout that r, the answer of an
-- open op, names. That is the session remembered for the checkout, while it
-- still exists. Else it is the session the action was run from, when r says
-- it may be adopted, and that session gets the checkout's label. Else it is
-- a new one. The id of an adopted or new session is remembered, in place of
-- one that is gone.
local function session_for(ctx, call, server, r)
  local id = r.session
  if id == nil or not session_exists(server, id) then
    if r.adopt and ctx.session_id ~= nil then
      id = ctx.session_id
      local renamed, err = server.call("session.set_label", { session_id = id, label = r.label })
      if renamed == nil then
        rex.log("warn", "projects: cannot rename the session: " .. tostring(err))
      end
    else
      -- A window in the API is a tab in the app.
      local session, failed = server.call("session.create", {
        label = r.label,
        initial_windows = { {
          window_label = "shell",
          layout = rex.layout.block{
            flavor = "com.superlogical.terminal.shell",
            -- The app's Startup Command setting only reaches the terminals
            -- the app makes itself, and a script cannot read it.
            options = { cwd = r.dir, shell = r.shell },
          },
        } },
      })
      if session == nil then fail(failed) end
      id = session.session_id
    end
    call("keep", { dir = r.dir, session = id })
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

-- close_session ends a session and stops what runs in it. A call on a
-- session other than the action's own fails until the caller attaches to it.
local function close_session(server, id)
  if not session_exists(server, id) then return end
  server.call("session.attach", { session_id = id })
  local closed, err = server.call("session.destroy", { session_id = id })
  if closed == nil then
    rex.log("warn", "projects: cannot close the worktree's session: " .. tostring(err))
  end
end

-- run is the body of Switch Branch in Project… (mode "here") and of Open
-- Worktree in Project… (mode "worktree"). Both ask for a project and a
-- branch; the mode decides what a branch without a worktree turns into.
local function run(ctx, mode)
  ctx = ctx or {}
  local call, server = connect(ctx)
  local worktree = mode == "worktree"

  -- The folder of the terminal the action was run from: its project is
  -- listed first, and its session may become the checkout's.
  local cwd = terminal_dir(ctx, server)

  -- 1. The project.
  local project = choose_project(ctx, call, worktree and "Open worktree" or "Switch branch", cwd)
  if project == nil then return end

  -- 2. The branch: a row, or a typed name. A plain folder has none.
  local list = call("branches", { project = project, mode = mode })
  local name, why = nil, nil
  if not list.plain then
    name, why = rex.ui.pick{
      title = (worktree and "Open worktree in " or "Switch branch in ") .. basename(project),
      placeholder = worktree and "Worktree, branch or new name" or "Branch or new name",
      allow_other = true,
      items = list.rows or {},
    }
    if name == nil then return stop(why) end
    name = typed_or_picked(name)
    if name == "" then return end
  end

  local args = {
    project = project,
    mode = mode,
    name = name,
    from = ctx.session_id,
    cwd = cwd,
  }
  local r = call("open", args)

  -- 3. For a new branch, what it starts from.
  if r.bases ~= nil then
    local base
    base, why = rex.ui.pick{
      title = "Start " .. r.name .. " from",
      placeholder = "Base branch",
      allow_other = true,
      items = r.bases,
    }
    if base == nil then return stop(why) end
    base = typed_or_picked(base)
    if base == "" then return end
    args.name, args.base = r.name, base
    r = call("open", args)
  end

  if r.why ~= nil then refuse(r.why) end
  if r.dir == nil then return end
  session_for(ctx, call, server, r)
end

-- clean_up is the body of Clean Up Branch in Project…: it removes one
-- branch, with its worktree and that worktree's session.
local function clean_up(ctx)
  ctx = ctx or {}
  local call, server = connect(ctx)
  local project = choose_project(ctx, call, "Clean up branch", terminal_dir(ctx, server))
  if project == nil then return end

  local list = call("branches", { project = project, mode = "cleanup" })
  if list.why ~= nil then refuse(list.why) end
  local branch, why = rex.ui.pick{
    title = "Clean up branch in " .. basename(project),
    placeholder = "Choose the branch to delete, with its worktree",
    items = list.rows or {},
  }
  if branch == nil then return stop(why) end

  local r = call("cleanup", { project = project, branch = branch })
  if r.why ~= nil then refuse(r.why) end

  -- Git keeps a branch whose commits are in no other branch, which is usual
  -- after a squash or rebase merge. Show its reason and offer to force.
  local failed
  if r.refused ~= nil then
    local answer = rex.ui.pick{
      title = trim(r.refused):match("^[^\r\n]*"),
      items = {
        { id = "keep", title = "Keep", subtitle = branch .. " and its commits stay" },
        { id = "force", title = "Force delete", subtitle = "git branch -D " .. branch },
      },
    }
    if answer == "force" then
      local forced = call("cleanup", { project = project, branch = branch, force = true })
      failed = forced.why
    end
  end

  -- The worktree is gone by now, so its session goes too, whatever became of
  -- the branch. It goes last, because this action may be running in it.
  if r.session ~= nil then close_session(server, r.session) end
  if failed ~= nil then refuse(failed) end
end

-- add_run is the body of Add Project to List…: it adds a project and opens
-- no session.
local function add_run(ctx)
  local call = connect(ctx or {})
  local _, why = add_project(call)
  stop(why)
end

-- remove_run is the body of Remove Project from List….
local function remove_run(ctx)
  local call = connect(ctx)
  local rows = call("saved").rows
  if rows == nil or #rows == 0 then return end
  local project = rex.ui.pick{
    title = "Remove project",
    placeholder = "Choose a project to forget (its folder stays)",
    items = rows,
  }
  if project == nil then return end
  call("forget", { project = project })
end

rex.action{
  name = "switch_project_branch",
  title = "Switch Branch in Project…",
  description = "Choose a project and a branch, switch the project's folder to it, and go to the project's session",
  category = "Projects",
  keywords = "checkout branch repository folder session new project",
  run = function(ctx) run(ctx, "here") end,
}

rex.action{
  name = "open_project_worktree",
  title = "Open Worktree in Project…",
  description = "Choose a project and a branch, and go to the session of the branch's worktree, making both when needed",
  category = "Projects",
  keywords = "worktree branch repository folder session new project",
  run = function(ctx) run(ctx, "worktree") end,
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
  name = "remove_project",
  title = "Remove Project from List…",
  description = "Forget a project that was added to the list; its folder stays",
  category = "Projects",
  keywords = "forget delete project list",
  run = remove_run,
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

-- M.setup changes the settings it is given and leaves the rest as they were.
function M.setup(opts)
  opts = opts or {}
  if opts.worktrees ~= nil then config.worktrees = opts.worktrees end
  if opts.roots ~= nil then config.roots = opts.roots end
  -- false goes back to the remote's default branch.
  if opts.base ~= nil then config.base = opts.base or nil end
  for _, key in ipairs({ "project_order", "branch_order" }) do
    local v = opts[key]
    if v == "recent" or v == "name" then
      config[key] = v
    elseif v ~= nil then
      rex.log("warn", "projects: " .. key .. " must be \"recent\" or \"name\", not " .. tostring(v))
    end
  end
  if opts.shell ~= nil then config.shell = opts.shell or nil end
  if opts.state_file ~= nil then config.state_file = opts.state_file; state = nil end
  if opts.key ~= nil then bind_key("key", opts.key) end
  if opts.worktree_key ~= nil then bind_key("worktree_key", opts.worktree_key) end
  return M
end

bind_key("key", config.key)
bind_key("worktree_key", config.worktree_key)

-- Pure helpers, for the tests in test/.
M._internal = {
  expand = expand, short = short, basename = basename, slashes = slashes,
  load_state = load_state, save_state = save_state, worktrees = worktrees,
  checkouts = checkouts, branch_rows = branch_rows, base_rows = base_rows,
  add_worktree = add_worktree, project_rows = project_rows,
  valid_branch_name = valid_branch_name, subfolders = subfolders,
  parent_of = parent_of, is_folder = is_folder, reason = reason, refuse = refuse,
  run = run, clean_up = clean_up, add_run = add_run, remove_run = remove_run,
  backend = backend, config = config,
  reset = function() state = nil end,
}

return M
