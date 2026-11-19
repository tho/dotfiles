-- rex-sort-sessions: sort the sessions on a host by name.
--
-- Adds one action, Sort Sessions by Name (sort_sessions), to the palette's
-- Sessions section. It sorts the sessions of the host the focused session is
-- on, A to Z, ignoring case. Sessions without a label go last, in the order
-- they had. The order is the server's, so every client sees it.
--
-- Install: put this file next to init.lua and add to init.lua
--
--     require("sort_sessions")
--
-- Optional, to bind a key:
--
--     require("sort_sessions").setup{ key = "ctrl+alt+cmd+s" }
--
-- For a session on a remote host the move runs on that host's server, called
-- from here, so the remote host does not need this file.

local M = {}

-- sort_key is what a session sorts by: its label without case. nil for a
-- session without one.
local function sort_key(s)
  if type(s.label) ~= "string" or s.label == "" then return nil end
  return s.label:lower()
end

-- sorted returns the sessions in the order they should end up in. Ties and
-- sessions without a label keep the order they had.
local function sorted(sessions)
  local rows = {}
  for i, s in ipairs(sessions) do rows[i] = { s = s, key = sort_key(s), i = i } end
  table.sort(rows, function(a, b)
    if a.key == nil or b.key == nil then
      if a.key ~= b.key then return b.key == nil end -- labelled first
      return a.i < b.i
    end
    if a.key ~= b.key then return a.key < b.key end
    if a.s.label ~= b.s.label then return a.s.label < b.s.label end
    return a.i < b.i
  end)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.s end
  return out
end

-- same_order reports whether two lists hold the same sessions in the same order.
local function same_order(a, b)
  for i = 1, #a do
    if a[i].session_id ~= b[i].session_id then return false end
  end
  return true
end

-- M.sort sorts the sessions on server, a table with a call function such as
-- rex or rex.server(label), and returns how many it moved.
function M.sort(server)
  local list, err = server.call("session.list")
  if list == nil then error("cannot list sessions: " .. tostring(err), 0) end
  local have = list.sessions or {}
  local want = sorted(have)
  if same_order(have, want) then return 0 end

  -- Place each session before the one that should follow it, from the back,
  -- so every anchor is already where it belongs.
  for i = #want, 1, -1 do
    local s, after = want[i], want[i + 1]
    local name = tostring(s.label or s.session_id)
    -- session.move works only on a session this connection is attached to.
    local ok, err = server.call("session.attach", { session_id = s.session_id })
    if ok == nil then error("cannot attach to session " .. name .. ": " .. tostring(err), 0) end
    local args = { session_id = s.session_id }
    if after ~= nil then args.before_session_id = after.session_id end
    ok, err = server.call("session.move", args)
    if ok == nil then error("cannot move session " .. name .. ": " .. tostring(err), 0) end
  end
  return #want
end

rex.action{
  name = "sort_sessions",
  title = "Sort Sessions by Name",
  description = "Sort the sessions on the focused session's host alphabetically, ignoring case",
  category = "Sessions",
  keywords = "sort order alphabetical name session reorder arrange",
  run = function(ctx)
    -- ctx.server names the host when the focused session is on another one.
    local server = (ctx and ctx.server) and rex.server(ctx.server) or rex
    return { moved = M.sort(server) }
  end,
}

-- M.setup binds a key to the action. Call it from init.lua, while it loads.
function M.setup(opts)
  opts = opts or {}
  if opts.key then rex.bind(opts.key, "sort_sessions") end
  return M
end

return M
