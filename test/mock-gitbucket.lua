-- Mock GitBucket server. GitBucket exposes a GitHub-compatible API at /api/v3/.
-- All responses use GitHub JSON format; confusio passes them through unchanged.
function OnHttpRequest()
  local path = GetPath()
  local method = GetMethod()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local REPO =
    '{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
    '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User","node_id":""},' ..
    '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",' ..
    '"fork":false,"url":"","clone_url":"http://localhost/octocat/hello-world.git",' ..
    '"homepage":"","stargazers_count":80,"watchers_count":80,"language":"JavaScript",' ..
    '"has_issues":true,"has_wiki":true,"forks_count":9,"archived":false,"disabled":false,' ..
    '"open_issues_count":0,"default_branch":"main","visibility":"public",' ..
    '"forks":9,"open_issues":0,"watchers":80,' ..
    '"created_at":"2011-01-26T19:01:12Z","updated_at":"2011-01-26T19:14:43Z",' ..
    '"pushed_at":"2011-01-26T19:06:43Z","node_id":""}'

  local rb = "/api/v3/repos/octocat/hello-world"

  if path == "/api/v3/rate_limit" then
    SetStatus(200, "OK")
    json('{"rate":{"limit":60,"remaining":60,"reset":9999999999}}')

  -- Repo -------------------------------------------------------------------
  elseif path == rb then
    SetStatus(200, "OK")
    json(REPO)

  elseif path == "/api/v3/user/repos" then
    SetStatus(200, "OK")
    json('[' .. REPO .. ']')

  elseif path == "/api/v3/orgs/testorg/repos" then
    SetStatus(200, "OK")
    json('[' .. REPO .. ']')

  -- Topics -----------------------------------------------------------------
  elseif path == rb .. "/topics" then
    SetStatus(200, "OK")
    json('{"names":["lua","api"]}')

  -- Languages --------------------------------------------------------------
  elseif path == rb .. "/languages" then
    SetStatus(200, "OK")
    json('{"JavaScript":12345,"Lua":6789}')

  -- Contributors -----------------------------------------------------------
  elseif path == rb .. "/contributors" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"contributions":100}]')

  -- Tags -------------------------------------------------------------------
  elseif path == rb .. "/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","commit":{"sha":"abc123def456","url":""}}]')

  -- Teams ------------------------------------------------------------------
  elseif path == rb .. "/teams" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"core","slug":"core","permission":"admin"}]')

  -- Branches ---------------------------------------------------------------
  elseif path == rb .. "/branches/main" then
    SetStatus(200, "OK")
    json('{"name":"main","commit":{"sha":"abc123def456","url":""},"protected":false}')

  elseif path == rb .. "/branches" then
    SetStatus(200, "OK")
    json('[{"name":"main","commit":{"sha":"abc123def456","url":""},"protected":false}]')

  -- Commits ----------------------------------------------------------------
  elseif path == rb .. "/statuses/abc123" then
    -- get_commit_statuses uses /statuses/{sha}
    SetStatus(200, "OK")
    json('[{"id":1,"state":"success","description":"Build passed","context":"ci",' ..
      '"target_url":"http://ci.example.com","created_at":"2020-01-01T00:00:00Z",' ..
      '"updated_at":"2020-01-01T00:00:00Z"}]')

  elseif path == rb .. "/commits/abc123/status" then
    -- get_commit_combined_status uses /commits/{sha}/status
    SetStatus(200, "OK")
    json('{"state":"success","statuses":[{"id":1,"state":"success","context":"ci"}],' ..
      '"total_count":1,"sha":"abc123def456"}')

  elseif path == rb .. "/commits/abc123/comments" then
    SetStatus(200, "OK")
    json('[{"id":1,"body":"Nice commit","user":{"login":"octocat"},' ..
      '"created_at":"2020-01-01T00:00:00Z"}]')

  elseif path == rb .. "/commits/abc123" then
    SetStatus(200, "OK")
    json('{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",' ..
      '"commit":{"message":"Initial commit","author":{"name":"Octocat",' ..
      '"email":"octocat@github.com","date":"2011-01-26T19:01:12Z"},' ..
      '"committer":{"name":"Octocat","email":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}}')

  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json('[{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",' ..
      '"commit":{"message":"Initial commit","author":{"name":"Octocat",' ..
      '"email":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}}]')

  -- Contents ---------------------------------------------------------------
  elseif path == rb .. "/readme" then
    SetStatus(200, "OK")
    json('{"name":"README.md","path":"README.md","sha":"abc123","size":100,' ..
      '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}')

  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/contents/") then
    local file = path:match("^" .. rb:gsub("%-", "%%-") .. "/contents/(.+)$") or "file"
    SetStatus(200, "OK")
    json('{"name":"' .. file .. '","path":"' .. file .. '","sha":"abc123","size":100,' ..
      '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}')

  -- Compare ----------------------------------------------------------------
  elseif path == rb .. "/compare/main...develop" then
    SetStatus(200, "OK")
    json('{"total_commits":3,"commits":[],"diff_stats":{"total":5}}')

  -- Collaborators ----------------------------------------------------------
  elseif path == rb .. "/collaborators" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"avatar_url":"","type":"User"}]')

  elseif path == rb .. "/collaborators/octocat/permission" then
    SetStatus(200, "OK")
    json('{"permission":"admin","user":{"login":"octocat","id":1}}')

  elseif path == rb .. "/collaborators/octocat" and method == "GET" then
    SetStatus(204, "No Content")

  -- Forks ------------------------------------------------------------------
  elseif path == rb .. "/forks" then
    SetStatus(200, "OK")
    json('[{"id":3,"name":"hello-world","full_name":"forker/hello-world","private":false,' ..
      '"owner":{"login":"forker","id":3,"avatar_url":"","url":"","html_url":"","type":"User","node_id":""},' ..
      '"default_branch":"main","fork":true,"visibility":"public"}]')

  -- Releases ---------------------------------------------------------------
  elseif path == rb .. "/releases/latest" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == rb .. "/releases/tags/v1.0" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == rb .. "/releases/1/assets" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"binary.zip","size":1024,"download_count":5,' ..
      '"browser_download_url":"http://localhost/attachments/1"}]')

  elseif path == rb .. "/releases/assets/1" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"binary.zip","size":1024,"download_count":5,' ..
      '"browser_download_url":"http://localhost/attachments/1"}')

  elseif path == rb .. "/releases/1" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == rb .. "/releases" then
    SetStatus(200, "OK")
    json('[{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}]')

  -- Deploy keys ------------------------------------------------------------
  elseif path == rb .. "/keys/1" then
    SetStatus(200, "OK")
    json('{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,' ..
      '"created_at":"2020-01-01T00:00:00Z"}')

  elseif path == rb .. "/keys" then
    SetStatus(200, "OK")
    json('[{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,' ..
      '"created_at":"2020-01-01T00:00:00Z"}]')

  -- Webhooks ---------------------------------------------------------------
  elseif path == rb .. "/hooks/1" then
    SetStatus(200, "OK")
    json('{"id":1,"type":"web","active":true,"events":["push"],' ..
      '"config":{"url":"https://example.com/hook","content_type":"json"}}')

  elseif path == rb .. "/hooks" then
    SetStatus(200, "OK")
    json('[{"id":1,"type":"web","active":true,"events":["push"],' ..
      '"config":{"url":"https://example.com/hook","content_type":"json"}}]')

  -- Repo-level commit comments ---------------------------------------------
  elseif path == rb .. "/comments/1" then
    SetStatus(200, "OK")
    json('{"id":1,"body":"Nice commit","user":{"login":"octocat"},' ..
      '"created_at":"2020-01-01T00:00:00Z"}')

  elseif path == rb .. "/comments" then
    SetStatus(200, "OK")
    json('[{"id":1,"body":"Nice commit","user":{"login":"octocat"},' ..
      '"created_at":"2020-01-01T00:00:00Z"}]')

  -- Users' repos -----------------------------------------------------------
  elseif path == "/api/v3/users/octocat/repos" then
    SetStatus(200, "OK")
    json('[' .. REPO .. ']')

  elseif path == "/api/v3/repositories" then
    SetStatus(200, "OK")
    json('[' .. REPO .. ']')

  -- Users (GitHub-compatible) ----------------------------------------------
  elseif path == "/api/v3/user" then
    SetStatus(200, "OK")
    json('{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"",' ..
      '"type":"User","site_admin":false,"name":"The Octocat","email":"octocat@github.com",' ..
      '"followers":100,"following":5}')

  elseif path == "/api/v3/users/octocat" then
    SetStatus(200, "OK")
    json('{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"",' ..
      '"type":"User","site_admin":false,"name":"The Octocat"}')

  elseif path == "/api/v3/users" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"","type":"User"}]')

  elseif path == "/api/v3/user/followers" then
    SetStatus(200, "OK")
    json('[{"login":"hubot","id":2,"node_id":"","avatar_url":"","html_url":"","type":"User"}]')

  elseif path == "/api/v3/user/following" then
    SetStatus(200, "OK")
    json('[]')

  elseif path == "/api/v3/user/following/hubot" then
    SetStatus(204, "No Content")

  elseif path == "/api/v3/users/octocat/followers" then
    SetStatus(200, "OK")
    json('[{"login":"hubot","id":2,"node_id":"","avatar_url":"","html_url":"","type":"User"}]')

  elseif path == "/api/v3/users/octocat/following" then
    SetStatus(200, "OK")
    json('[]')

  elseif path == "/api/v3/user/emails" then
    SetStatus(200, "OK")
    json('[{"email":"octocat@github.com","verified":true,"primary":true,"visibility":"public"}]')

  elseif path == "/api/v3/user/keys" then
    SetStatus(200, "OK")
    json('[{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key"}]')

  elseif path == "/api/v3/user/keys/1" then
    SetStatus(200, "OK")
    json('{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key"}')

  elseif path == "/api/v3/users/octocat/keys" then
    SetStatus(200, "OK")
    json('[{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key"}]')

  -- Teams -------------------------------------------------------------------
  elseif path == "/api/v3/orgs/testorg/teams" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"core","slug":"core","description":"Core team",' ..
      '"privacy":"closed","permission":"push","members_url":"","repositories_url":""}]')

  elseif path == "/api/v3/orgs/testorg/teams/core" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"core","slug":"core","description":"Core team",' ..
      '"privacy":"closed","permission":"push","members_url":"","repositories_url":""}')

  elseif path == "/api/v3/orgs/testorg/teams/core/members" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"","type":"User"}]')

  elseif path == "/api/v3/orgs/testorg/teams/core/memberships/octocat" then
    SetStatus(200, "OK")
    json('{"url":"","role":"member","state":"active"}')

  elseif path == "/api/v3/orgs/testorg/teams/core/repos" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
      '"owner":{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"","type":"User"},' ..
      '"html_url":"","default_branch":"main","visibility":"public"}]')

  elseif path == "/api/v3/orgs/testorg/teams/core/repos/octocat/hello-world" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
      '"owner":{"login":"octocat","id":1,"node_id":"","avatar_url":"","html_url":"","type":"User"},' ..
      '"html_url":"","default_branch":"main","visibility":"public"}')

  elseif path == "/api/v3/orgs/testorg/teams/core/invitations" then
    SetStatus(200, "OK")
    json('[]')

  elseif path == "/api/v3/orgs/testorg/teams/core/teams" then
    SetStatus(200, "OK")
    json('[]')

  else
    SetStatus(404, "Not Found")
  end
end
