-- Segment-based radix trie router (global: route_add, route_match, path_known).
--
-- Each node: { static = {[segment]→node}, param = node|nil, handler = name|nil }
--
-- Routes are registered as "VERB /path" strings. The verb becomes the first
-- static segment in the trie so each verb+path combination has its own handler.
-- Static edges are preferred over param edges at each node, so /repos/search
-- beats /repos/{owner} when both are registered.
--
-- A second path-only trie tracks which paths are known at all; when a verb+path
-- lookup misses but the path is known, OnHttpRequest returns 405 rather than
-- 404. Unknown paths return JSON 404 directly; Route() is no longer called.

local function new_node()
  return { static = {}, param = nil, handler = nil }
end
local trie = new_node()
local path_trie = new_node()

local function _trie_insert(t, key)
  local node = t
  for seg in key:gmatch("[^/]+") do
    if seg:sub(1, 1) == "{" then
      node.param = node.param or new_node()
      node = node.param
      -- {param+} is a greedy capture: matches this segment and all remaining segments.
      if seg:sub(-2) == "+}" then
        node.greedy = true
        break
      end
    else
      node.static[seg] = node.static[seg] or new_node()
      node = node.static[seg]
    end
  end
  return node
end

local function _trie_walk(root, key)
  local node = root
  local caps = {}
  local segs = {}
  for seg in key:gmatch("[^/]+") do
    segs[#segs + 1] = seg
  end
  local i = 1
  while i <= #segs do
    local seg = segs[i]
    if node.static[seg] then
      node = node.static[seg]
    elseif node.param then
      node = node.param
      if node.greedy then
        caps[#caps + 1] = table.concat(segs, "/", i)
        return node, caps
      end
      caps[#caps + 1] = seg
    else
      return nil
    end
    i = i + 1
  end
  return node, caps
end

-- route_add("VERB /path", handler_name [, default_fn])
-- e.g. route_add("GET /repos/{owner}/{repo}", "get_repo")
-- When default_fn is given it is used if the backend has no handler for handler_name.
function route_add(route, handler_name, default_fn) -- luacheck: globals route_add
  local verb, path = route:match("^(%S+)%s+(.+)$")
  local n = _trie_insert(trie, verb .. path)
  n.handler = handler_name
  n.default = default_fn
  _trie_insert(path_trie, path).handler = true
end

-- route_match returns handler_name, captures, default_fn for a matched route,
-- or nil, nil, nil when no route matches.
function route_match(method, path) -- luacheck: globals route_match
  local node, caps = _trie_walk(trie, method .. path)
  if node then
    return node.handler, caps, node.default
  end
  return nil, nil, nil
end

-- path_known returns true when the path matches a registered route (any verb).
-- Used by OnHttpRequest to distinguish 404 (unknown path) from 405 (wrong verb).
function path_known(path) -- luacheck: globals path_known
  local node = _trie_walk(path_trie, path)
  return node ~= nil and node.handler == true
end
