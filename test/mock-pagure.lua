-- Mock Pagure server. Uses Pagure REST API at /api/0/.
-- confusio translates Pagure responses to GitHub format.
function OnHttpRequest()
  local path = GetPath()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local function raw(body)
    SetHeader("Content-Type", "text/plain")
    Write(body)
  end

  local REPO = '{"id":1,"name":"hello-world","fullname":"octocat/hello-world",'
    .. '"namespace":"","user":{"name":"octocat","url_path":"user/octocat"},'
    .. '"description":"My first repo","private":false,"default_branch":"main",'
    .. '"stars":5,"forks_count":2,'
    .. '"date_created":"2011-01-26T19:01:12Z","date_modified":"2011-01-26T19:14:43Z",'
    .. '"url_path":"octocat/hello-world",'
    .. '"full_url":"http://localhost/octocat/hello-world.git",'
    .. '"tags":["lua","api"],"forks":[]}'

  local rp = "/api/0/octocat/hello-world"

  if path == "/api/0/version" then
    SetStatus(200, "OK")
    json('{"version":"5.13.3"}')

  -- whoami -----------------------------------------------------------------
  elseif path == "/api/0/-/whoami" then
    SetStatus(200, "OK")
    json('{"username":"octocat"}')

  -- Repo -------------------------------------------------------------------
  elseif path == rp then
    SetStatus(200, "OK")
    json(REPO)

  -- User repos -------------------------------------------------------------
  elseif path == "/api/0/user/octocat/projects" then
    SetStatus(200, "OK")
    json('{"repos":[' .. REPO .. '],"total_projects":1}')

  -- Org (namespace) repos --------------------------------------------------
  elseif path == "/api/0/projects" then
    SetStatus(200, "OK")
    json('{"projects":[' .. REPO .. '],"total_projects":1}')

  -- Branches ---------------------------------------------------------------
  elseif path == rp .. "/git/branches" then
    SetStatus(200, "OK")
    json('{"branches":["main","develop"],"total_branches":2}')

  -- Commits ----------------------------------------------------------------
  elseif path == rp .. "/commits" then
    SetStatus(200, "OK")
    json(
      '{"commits":[{"id":"abc123def456","message":"Initial commit",'
        .. '"date":"2011-01-26T19:01:12+00:00","date_utc":"2011-01-26T19:01:12Z",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com"}}],'
        .. '"total_commits":1}'
    )

  -- Tags -------------------------------------------------------------------
  elseif path == rp .. "/git/tags" then
    SetStatus(200, "OK")
    json('{"tags":["v1.0","v2.0"]}')

  -- Contents (raw bytes) ---------------------------------------------------
  elseif path == rp .. "/raw/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")
  elseif path:find("^" .. rp:gsub("%-", "%%-") .. "/raw/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Issues -----------------------------------------------------------------
  -- Individual issue (Pagure uses /issue/{id} singular)
  elseif path == rp .. "/issue/9999" then
    SetStatus(404, "Not Found")
    json('{"error":"Issue not found","error_code":"ENOISSUE"}')
  elseif path == rp .. "/issue/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"title":"Found a bug","content":"Bug description",'
        .. '"status":"Open",'
        .. '"user":{"name":"octocat","fullname":"The Octocat","url_path":"user/octocat","avatar_url":""},'
        .. '"assignee":null,'
        .. '"tags":["bug"],'
        .. '"date_created":"1577836800","last_updated":"1577923200",'
        .. '"full_url":"octocat/hello-world/issue/1",'
        .. '"comments":[{"id":1,"comment":"This is a comment",'
        .. '"user":{"name":"octocat","fullname":"The Octocat","url_path":"user/octocat","avatar_url":""},'
        .. '"date_created":"1577836800"}]}'
    )
  elseif path == rp .. "/issues" then
    SetStatus(200, "OK")
    json(
      '{"issues":[{"id":1,"title":"Found a bug","content":"Bug description",'
        .. '"status":"Open",'
        .. '"user":{"name":"octocat","fullname":"The Octocat","url_path":"user/octocat","avatar_url":""},'
        .. '"assignee":null,'
        .. '"tags":["bug"],'
        .. '"date_created":"1577836800","last_updated":"1577923200",'
        .. '"full_url":"octocat/hello-world/issue/1","comments":[]}],'
        .. '"total_issues":1}'
    )

  -- Users -------------------------------------------------------------------
  elseif path == "/api/0/user/octocat" then
    SetStatus(200, "OK")
    json('{"user":{"username":"octocat","fullname":"The Octocat","avatar_url":""}}')
  elseif path == "/api/0/users" then
    SetStatus(200, "OK")
    local ufilter = GetParam("username")
    if ufilter and ufilter ~= "" then
      -- Pagure filters by username prefix; simulate by returning only octocat when queried.
      if ("octocat"):find(ufilter, 1, true) then
        json('{"users":["octocat"],"total_users":1}')
      else
        json('{"users":[],"total_users":0}')
      end
    else
      json('{"users":["octocat","hubot"],"total_users":2}')
    end

  -- Users' repos -----------------------------------------------------------
  elseif path:find("^/api/0/user/") then
    SetStatus(200, "OK")
    json('{"repos":[' .. REPO .. '],"total_projects":1}')

  -- Public repos -----------------------------------------------------------
  elseif path == "/api/0/repos" then
    SetStatus(200, "OK")
    json('{"projects":[' .. REPO .. '],"total_projects":1}')

  -- Commit flags (Checks API) ----------------------------------------------
  elseif path:find("^" .. rp:gsub("%-", "%%-") .. "/c/[^/]+/flag$") then
    local method = GetMethod()
    if method == "POST" then
      SetStatus(201, "Created")
      json(
        '{"flag":{"uid":"ci/test","username":"ci/test","percent":0,'
          .. '"comment":"Build started","url":"https://ci.example.com/build/1",'
          .. '"status":"pending","date_created":"1577836800","date_updated":"1577836800"},'
          .. '"message":"Flag added"}'
      )
    else
      SetStatus(200, "OK")
      json(
        '{"flags":[{"uid":"ci/test","username":"ci/test","percent":100,'
          .. '"comment":"Build passed","url":"https://ci.example.com/build/1",'
          .. '"status":"success","date_created":"1577836800","date_updated":"1577923200"}]}'
      )
    end

  -- Migrations ----------------------------------------------------------------
  -- Pagure has no GitHub-style org/user migration API; confusio
  -- returns fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")
  else
    SetStatus(404, "Not Found")
  end
end
