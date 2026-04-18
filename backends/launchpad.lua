-- Launchpad backend handler overrides.
-- Uses Launchpad REST API (Malone) at /devel/.
-- Bug tracker: /devel/~{owner}/{repo}?ws.op=searchTasks for issue lists.
-- Individual bugs: /devel/bugs/{id} (global bug numbers).
if config.base_url == "" then
  config.base_url = "https://api.launchpad.net"
end

local function fetch_json(url)
  return pcall(Fetch, url, nil)
end

local CLOSED_STATUSES = {
  ["Fix Released"] = true,
  ["Invalid"] = true,
  ["Won't Fix"] = true,
  ["Fix Committed"] = true,
}

-- Extract Launchpad username from an owner/assignee link like ".../~username".
local function lp_login(link)
  return (link or ""):match("/~([^/]+)$") or ""
end

-- Translate a Launchpad bug task (IBugTask) to GitHub issue format.
-- Bug tasks come from searchTasks; they have status but not description.
local function translate_lp_task(t)
  if not t then
    return {}
  end
  local bug_id = tonumber((t.bug_link or ""):match("/bugs/(%d+)$")) or 0
  local state = CLOSED_STATUSES[t.status or ""] and "closed" or "open"
  return {
    id = bug_id,
    node_id = "",
    number = bug_id,
    title = t.title or "",
    body = "",
    state = state,
    user = {
      login = lp_login(t.owner_link),
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      type = "User",
    },
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = t.date_created or "",
    updated_at = t.date_last_updated or t.date_created or "",
    closed_at = t.date_closed,
    html_url = "",
  }
end

-- Translate a Launchpad IBug + optional IBugTask to GitHub issue format.
-- Bug has title/description/reporter; task has per-project status.
local function translate_lp_bug(bug, task)
  if not bug then
    return {}
  end
  local state = "open"
  if task then
    state = CLOSED_STATUSES[task.status or ""] and "closed" or "open"
  end
  return {
    id = bug.id or 0,
    node_id = "",
    number = bug.id or 0,
    title = bug.title or "",
    body = bug.description or "",
    state = state,
    user = {
      login = lp_login(bug.owner_link),
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      type = "User",
    },
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = bug.date_created or "",
    updated_at = bug.date_last_updated or bug.date_created or "",
    closed_at = nil,
    html_url = "",
  }
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/devel/"))
end)

-- Issues --------------------------------------------------------------------
-- Launchpad: GET /devel/~{owner}/{repo}?ws.op=searchTasks

b:rest("get_repo_issues", function(owner, repo_name)
  local state = GetParam("state") or "open"
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  local url = config.base_url
    .. "/devel/~"
    .. owner
    .. "/"
    .. repo_name
    .. "?ws.op=searchTasks"
    .. "&start="
    .. ((page - 1) * count)
    .. "&limit="
    .. count
  if state == "closed" then
    url = url .. "&status=Fix+Released&status=Invalid&status=Won%27t+Fix&status=Fix+Committed"
  elseif state ~= "all" then
    url = url .. "&status=New&status=Incomplete&status=Confirmed&status=Triaged&status=In+Progress"
  end
  proxy_json(function(data)
    return translate_list(translate_lp_task, data.entries)
  end, fetch_json(url))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
-- Fetch the bug object (title/description) and its project task (status).
b:rest("get_repo_issue", function(owner, repo_name, issue_number)
  local ok, status, _, body = fetch_json(config.base_url .. "/devel/bugs/" .. issue_number)
  if not ok then
    respond_json(503, {})
    return
  end
  if status == 404 then
    respond_json(404, { message = "Not Found" })
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local bug = DecodeJson(body)
  local task_url = config.base_url
    .. "/devel/~"
    .. owner
    .. "/"
    .. repo_name
    .. "/+bug/"
    .. issue_number
  local ok2, status2, _, body2 = fetch_json(task_url)
  local task = (ok2 and status2 == 200) and DecodeJson(body2) or nil
  respond_json(200, translate_lp_bug(bug, task))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
-- Launchpad: GET /devel/bugs/{id}/messages
-- The first message (index 0) is the bug description, so skip it.
b:rest("get_issue_comments", function(_owner, _repo_name, issue_number)
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  -- Offset by 1 to skip the description message (always first in the collection).
  local start = (page - 1) * count + 1
  local url = config.base_url
    .. "/devel/bugs/"
    .. issue_number
    .. "/messages?start="
    .. start
    .. "&limit="
    .. count
  proxy_json(function(data)
    local entries = data.entries or {}
    local result = {}
    for _, m in ipairs(entries) do
      result[#result + 1] = {
        id = m.index or 0,
        node_id = "",
        url = "",
        body = m.content or "",
        user = {
          login = lp_login(m.owner_link),
          id = 0,
          node_id = "",
          avatar_url = "",
          url = "",
          type = "User",
        },
        created_at = m.date_created or "",
        updated_at = m.date_created or "",
        html_url = "",
      }
    end
    return result
  end, fetch_json(url))
end)

b:build()
