function OnHttpRequest()
  local path = GetPath()
  local method = GetMethod()
  local auth = GetHeader("Authorization")
  if auth ~= nil and auth ~= "token testtoken" then
    SetStatus(401, "Unauthorized")
    return
  end

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  if path == "/api/v1/version" then
    SetStatus(200, "OK")
    json('{"version":"1.20.0"}')

  -- Repo -------------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
      '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User"},' ..
      '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",' ..
      '"fork":false,"url":"","clone_url":"http://localhost/octocat/hello-world.git",' ..
      '"homepage":"","stargazers_count":80,"watchers_count":80,"language":"JavaScript",' ..
      '"has_issues":true,"has_wiki":true,"forks_count":9,"archived":false,"disabled":false,' ..
      '"open_issues_count":0,"default_branch":"main","visibility":"public",' ..
      '"forks":9,"open_issues":0,"watchers":80,' ..
      '"created_at":"2011-01-26T19:01:12Z","updated_at":"2011-01-26T19:14:43Z",' ..
      '"pushed_at":"2011-01-26T19:06:43Z"}')

  elseif path == "/api/v1/user/repos" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
      '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User"},' ..
      '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",' ..
      '"fork":false,"url":"","clone_url":"http://localhost/octocat/hello-world.git",' ..
      '"homepage":"","stargazers_count":80,"watchers_count":80,"language":"JavaScript",' ..
      '"has_issues":true,"has_wiki":true,"forks_count":9,"archived":false,"disabled":false,' ..
      '"open_issues_count":0,"default_branch":"main","visibility":"public",' ..
      '"forks":9,"open_issues":0,"watchers":80,' ..
      '"created_at":"2011-01-26T19:01:12Z","updated_at":"2011-01-26T19:14:43Z",' ..
      '"pushed_at":"2011-01-26T19:06:43Z"}]')

  elseif path == "/api/v1/users/octocat/repos" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
      '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User"},' ..
      '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",' ..
      '"fork":false,"url":"","clone_url":"http://localhost/octocat/hello-world.git",' ..
      '"homepage":"","stargazers_count":80,"watchers_count":80,"language":"JavaScript",' ..
      '"has_issues":true,"has_wiki":true,"forks_count":9,"archived":false,"disabled":false,' ..
      '"open_issues_count":0,"default_branch":"main","visibility":"public",' ..
      '"forks":9,"open_issues":0,"watchers":80,' ..
      '"created_at":"2011-01-26T19:01:12Z","updated_at":"2011-01-26T19:14:43Z",' ..
      '"pushed_at":"2011-01-26T19:06:43Z"}]')

  elseif path == "/api/v1/orgs/testorg/repos" then
    SetStatus(200, "OK")
    json('[{"id":2,"name":"org-repo","full_name":"testorg/org-repo","private":false,' ..
      '"owner":{"login":"testorg","id":2,"avatar_url":"","url":"","html_url":"","type":"Organization"},' ..
      '"html_url":"http://localhost/testorg/org-repo","description":"Org repo",' ..
      '"fork":false,"url":"","clone_url":"http://localhost/testorg/org-repo.git",' ..
      '"homepage":"","stargazers_count":0,"watchers_count":0,"language":null,' ..
      '"has_issues":true,"has_wiki":true,"forks_count":0,"archived":false,"disabled":false,' ..
      '"open_issues_count":0,"default_branch":"main","visibility":"public",' ..
      '"forks":0,"open_issues":0,"watchers":0,' ..
      '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",' ..
      '"pushed_at":"2020-01-01T00:00:00Z"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/topics" then
    SetStatus(200, "OK")
    json('{"topics":["lua","api"]}')

  elseif path == "/api/v1/repos/octocat/hello-world/languages" then
    SetStatus(200, "OK")
    json('{"JavaScript":12345,"Lua":6789}')

  elseif path == "/api/v1/repos/octocat/hello-world/contributors" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"contributions":100}]')

  elseif path == "/api/v1/repos/octocat/hello-world/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","id":"abc123","message":"","commit":{"sha":"abc123def456","url":""}}]')

  -- Branches ---------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/branches" then
    SetStatus(200, "OK")
    json('[{"name":"main","commit":{"id":"abc123def456","message":"Initial commit",' ..
      '"url":"http://localhost/octocat/hello-world/commit/abc123def456"},"protected":false}]')

  elseif path == "/api/v1/repos/octocat/hello-world/branches/main" then
    SetStatus(200, "OK")
    json('{"name":"main","commit":{"id":"abc123def456","message":"Initial commit",' ..
      '"url":"http://localhost/octocat/hello-world/commit/abc123def456"},"protected":false}')

  -- Commits ----------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/commits" then
    SetStatus(200, "OK")
    json('[{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",' ..
      '"commit":{"message":"Initial commit","author":{"name":"Octocat","email":"octocat@github.com",' ..
      '"date":"2011-01-26T19:01:12Z"}}}]')

  elseif path == "/api/v1/repos/octocat/hello-world/git/commits/abc123" then
    SetStatus(200, "OK")
    json('{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",' ..
      '"commit":{"message":"Initial commit","author":{"name":"Octocat","email":"octocat@github.com",' ..
      '"date":"2011-01-26T19:01:12Z"}}}')

  elseif path == "/api/v1/repos/octocat/hello-world/statuses/abc123" then
    SetStatus(200, "OK")
    json('[{"id":1,"state":"success","description":"Build passed","context":"ci"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/commits/abc123/statuses" then
    SetStatus(200, "OK")
    json('[{"id":1,"state":"success","description":"Build passed","context":"ci"}]')

  -- Contents ---------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/readme" then
    SetStatus(200, "OK")
    json('{"name":"README.md","path":"README.md","sha":"abc123","size":100,' ..
      '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}')

  elseif path:find("^/api/v1/repos/octocat/hello%-world/contents/") then
    SetStatus(200, "OK")
    local file = path:match("^/api/v1/repos/octocat/hello%-world/contents/(.+)$") or "file"
    json('{"name":"' .. file .. '","path":"' .. file .. '","sha":"abc123","size":100,' ..
      '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}')

  -- Collaborators ----------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/collaborators" then
    SetStatus(200, "OK")
    json('[{"login":"octocat","id":1,"avatar_url":"","type":"User"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/collaborators/octocat" and method == "GET" then
    SetStatus(204, "No Content")

  elseif path == "/api/v1/repos/octocat/hello-world/collaborators/octocat/permission" then
    SetStatus(200, "OK")
    json('{"permission":"admin","user":{"login":"octocat","id":1}}')

  -- Forks ------------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/forks" then
    SetStatus(200, "OK")
    json('[{"id":3,"name":"hello-world","full_name":"forker/hello-world","private":false,' ..
      '"owner":{"login":"forker","id":3,"avatar_url":"","url":"","html_url":"","type":"User"},' ..
      '"html_url":"http://localhost/forker/hello-world","description":"Fork",' ..
      '"fork":true,"url":"","clone_url":"http://localhost/forker/hello-world.git",' ..
      '"default_branch":"main","visibility":"public"}]')

  -- Releases ---------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/releases" then
    SetStatus(200, "OK")
    json('[{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}]')

  elseif path == "/api/v1/repos/octocat/hello-world/releases/latest" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == "/api/v1/repos/octocat/hello-world/releases/tags/v1.0" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == "/api/v1/repos/octocat/hello-world/releases/1" then
    SetStatus(200, "OK")
    json('{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",' ..
      '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",' ..
      '"published_at":"2020-01-01T00:00:00Z","assets":[]}')

  elseif path == "/api/v1/repos/octocat/hello-world/releases/1/assets" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"binary.zip","size":1024,"download_count":5,' ..
      '"browser_download_url":"http://localhost/attachments/1"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/releases/assets/1" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"binary.zip","size":1024,"download_count":5,' ..
      '"browser_download_url":"http://localhost/attachments/1"}')

  -- Deploy keys ------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/keys" then
    SetStatus(200, "OK")
    json('[{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,' ..
      '"created_at":"2020-01-01T00:00:00Z"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/keys/1" then
    SetStatus(200, "OK")
    json('{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,' ..
      '"created_at":"2020-01-01T00:00:00Z"}')

  -- Webhooks ---------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/hooks" then
    SetStatus(200, "OK")
    json('[{"id":1,"type":"gitea","active":true,"events":["push"],' ..
      '"config":{"url":"https://example.com/hook","content_type":"json"}}]')

  elseif path == "/api/v1/repos/octocat/hello-world/hooks/1" then
    SetStatus(200, "OK")
    json('{"id":1,"type":"gitea","active":true,"events":["push"],' ..
      '"config":{"url":"https://example.com/hook","content_type":"json"}}')

  -- Compare ----------------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/compare/main...develop" then
    SetStatus(200, "OK")
    json('{"total_commits":3,"commits":[],"diff_stats":{"total":5,"additions":20,"deletions":5}}')

  -- Repo comments ----------------------------------------------------------
  elseif path == "/api/v1/repos/octocat/hello-world/comments" then
    SetStatus(200, "OK")
    json('[{"id":1,"body":"Nice commit","user":{"login":"octocat"},"created_at":"2020-01-01T00:00:00Z"}]')

  elseif path == "/api/v1/repos/octocat/hello-world/comments/1" then
    SetStatus(200, "OK")
    json('{"id":1,"body":"Nice commit","user":{"login":"octocat"},"created_at":"2020-01-01T00:00:00Z"}')

  else
    SetStatus(404, "Not Found")
  end
end
