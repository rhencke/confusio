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

  -- Shared response bodies
  local REPO = '{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,'
    .. '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User"},'
    .. '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",'
    .. '"fork":false,"url":"","clone_url":"http://localhost/octocat/hello-world.git",'
    .. '"homepage":"","stargazers_count":80,"watchers_count":80,"language":"JavaScript",'
    .. '"has_issues":true,"has_wiki":true,"forks_count":9,"archived":false,"disabled":false,'
    .. '"open_issues_count":0,"default_branch":"main","visibility":"public",'
    .. '"forks":9,"open_issues":0,"watchers":80,'
    .. '"created_at":"2011-01-26T19:01:12Z","updated_at":"2011-01-26T19:14:43Z",'
    .. '"pushed_at":"2011-01-26T19:06:43Z"}'

  local USER = '{"login":"octocat","id":1,"avatar_url":"","html_url":"http://localhost/octocat",'
    .. '"full_name":"The Octocat","email":"octocat@github.com","is_admin":false,'
    .. '"location":"San Francisco","website":"https://github.blog",'
    .. '"followers_count":100,"following_count":5,"created":"2011-01-25T18:44:36Z"}'

  local FOLLOWER = '[{"login":"hubot","id":2,"avatar_url":"","html_url":"","full_name":"Hubot",'
    .. '"email":"","is_admin":false,"location":"","website":"","followers_count":0,'
    .. '"following_count":0,"created":"2020-01-01T00:00:00Z"}]'

  local RELEASE = '{"id":1,"tag_name":"v1.0","name":"Release 1.0","body":"First release",'
    .. '"draft":false,"prerelease":false,"created_at":"2020-01-01T00:00:00Z",'
    .. '"published_at":"2020-01-01T00:00:00Z","assets":[]}'

  -- Table-driven dispatch. Keys: exact path (any method) or "METHOD /path".
  -- Values: {status, body} — body nil means no body (e.g. 204).
  local routes = {
    ["/api/v1/version"] = { 200, '{"version":"1.20.0"}' },

    -- Repos
    ["/api/v1/repos/octocat/hello-world"] = { 200, REPO },
    ["/api/v1/user/repos"] = { 200, "[" .. REPO .. "]" },
    ["/api/v1/users/octocat/repos"] = { 200, "[" .. REPO .. "]" },
    ["/api/v1/orgs/testorg/repos"] = {
      200,
      '[{"id":2,"name":"org-repo","full_name":"testorg/org-repo","private":false,'
        .. '"owner":{"login":"testorg","id":2,"avatar_url":"","url":"","html_url":"","type":"Organization"},'
        .. '"html_url":"http://localhost/testorg/org-repo","description":"Org repo",'
        .. '"fork":false,"url":"","clone_url":"http://localhost/testorg/org-repo.git",'
        .. '"homepage":"","stargazers_count":0,"watchers_count":0,"language":null,'
        .. '"has_issues":true,"has_wiki":true,"forks_count":0,"archived":false,"disabled":false,'
        .. '"open_issues_count":0,"default_branch":"main","visibility":"public",'
        .. '"forks":0,"open_issues":0,"watchers":0,'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
        .. '"pushed_at":"2020-01-01T00:00:00Z"}]',
    },
    ["/api/v1/repos/octocat/hello-world/topics"] = { 200, '{"topics":["lua","api"]}' },
    ["/api/v1/repos/octocat/hello-world/languages"] = { 200, '{"JavaScript":12345,"Lua":6789}' },
    ["/api/v1/repos/octocat/hello-world/contributors"] = {
      200,
      '[{"login":"octocat","id":1,"contributions":100}]',
    },
    ["/api/v1/repos/octocat/hello-world/tags"] = {
      200,
      '[{"name":"v1.0","id":"abc123","message":"","commit":{"sha":"abc123def456","url":""}}]',
    },

    -- Branches
    ["/api/v1/repos/octocat/hello-world/branches"] = {
      200,
      '[{"name":"main","commit":{"id":"abc123def456","message":"Initial commit",'
        .. '"url":"http://localhost/octocat/hello-world/commit/abc123def456"},"protected":false}]',
    },
    ["/api/v1/repos/octocat/hello-world/branches/main"] = {
      200,
      '{"name":"main","commit":{"id":"abc123def456","message":"Initial commit",'
        .. '"url":"http://localhost/octocat/hello-world/commit/abc123def456"},"protected":false}',
    },

    -- Commits
    ["/api/v1/repos/octocat/hello-world/commits"] = {
      200,
      '[{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",'
        .. '"commit":{"message":"Initial commit","author":{"name":"Octocat","email":"octocat@github.com",'
        .. '"date":"2011-01-26T19:01:12Z"}}}]',
    },
    ["/api/v1/repos/octocat/hello-world/git/commits/abc123"] = {
      200,
      '{"sha":"abc123def456","html_url":"http://localhost/octocat/hello-world/commit/abc123def456",'
        .. '"commit":{"message":"Initial commit","author":{"name":"Octocat","email":"octocat@github.com",'
        .. '"date":"2011-01-26T19:01:12Z"}}}',
    },
    ["/api/v1/repos/octocat/hello-world/statuses/abc123"] = {
      200,
      '[{"id":1,"state":"success","description":"Build passed","context":"ci"}]',
    },
    ["/api/v1/repos/octocat/hello-world/commits/abc123/statuses"] = {
      200,
      '[{"id":1,"state":"success","description":"Build passed","context":"ci"}]',
    },

    -- Contents
    ["/api/v1/repos/octocat/hello-world/readme"] = {
      200,
      '{"name":"README.md","path":"README.md","sha":"abc123","size":100,'
        .. '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}',
    },

    -- Collaborators
    ["/api/v1/repos/octocat/hello-world/collaborators"] = {
      200,
      '[{"login":"octocat","id":1,"avatar_url":"","type":"User"}]',
    },
    ["GET /api/v1/repos/octocat/hello-world/collaborators/octocat"] = { 204, nil },
    ["/api/v1/repos/octocat/hello-world/collaborators/octocat/permission"] = {
      200,
      '{"permission":"admin","user":{"login":"octocat","id":1}}',
    },

    -- Forks
    ["/api/v1/repos/octocat/hello-world/forks"] = {
      200,
      '[{"id":3,"name":"hello-world","full_name":"forker/hello-world","private":false,'
        .. '"owner":{"login":"forker","id":3,"avatar_url":"","url":"","html_url":"","type":"User"},'
        .. '"html_url":"http://localhost/forker/hello-world","description":"Fork",'
        .. '"fork":true,"url":"","clone_url":"http://localhost/forker/hello-world.git",'
        .. '"default_branch":"main","visibility":"public"}]',
    },

    -- Releases
    ["/api/v1/repos/octocat/hello-world/releases"] = { 200, "[" .. RELEASE .. "]" },
    ["/api/v1/repos/octocat/hello-world/releases/latest"] = { 200, RELEASE },
    ["/api/v1/repos/octocat/hello-world/releases/tags/v1.0"] = { 200, RELEASE },
    ["/api/v1/repos/octocat/hello-world/releases/1"] = { 200, RELEASE },
    ["/api/v1/repos/octocat/hello-world/releases/1/assets"] = {
      200,
      '[{"id":1,"name":"binary.zip","size":1024,"download_count":5,'
        .. '"browser_download_url":"http://localhost/attachments/1"}]',
    },
    ["/api/v1/repos/octocat/hello-world/releases/assets/1"] = {
      200,
      '{"id":1,"name":"binary.zip","size":1024,"download_count":5,'
        .. '"browser_download_url":"http://localhost/attachments/1"}',
    },

    -- Deploy keys
    ["/api/v1/repos/octocat/hello-world/keys"] = {
      200,
      '[{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,'
        .. '"created_at":"2020-01-01T00:00:00Z"}]',
    },
    ["/api/v1/repos/octocat/hello-world/keys/1"] = {
      200,
      '{"id":1,"key":"ssh-rsa AAAAB3...","title":"my key","read_only":true,'
        .. '"created_at":"2020-01-01T00:00:00Z"}',
    },

    -- Webhooks
    ["/api/v1/repos/octocat/hello-world/hooks"] = {
      200,
      '[{"id":1,"type":"gitea","active":true,"events":["push"],'
        .. '"config":{"url":"https://example.com/hook","content_type":"json"}}]',
    },
    ["/api/v1/repos/octocat/hello-world/hooks/1"] = {
      200,
      '{"id":1,"type":"gitea","active":true,"events":["push"],'
        .. '"config":{"url":"https://example.com/hook","content_type":"json"}}',
    },

    -- Compare
    ["/api/v1/repos/octocat/hello-world/compare/main...develop"] = {
      200,
      '{"total_commits":3,"commits":[],"diff_stats":{"total":5,"additions":20,"deletions":5}}',
    },

    -- Repo comments
    ["/api/v1/repos/octocat/hello-world/comments"] = {
      200,
      '[{"id":1,"body":"Nice commit","user":{"login":"octocat"},"created_at":"2020-01-01T00:00:00Z"}]',
    },
    ["/api/v1/repos/octocat/hello-world/comments/1"] = {
      200,
      '{"id":1,"body":"Nice commit","user":{"login":"octocat"},"created_at":"2020-01-01T00:00:00Z"}',
    },

    -- Users
    ["GET /api/v1/user"] = { 200, USER },
    ["PATCH /api/v1/user/settings"] = { 200, USER },
    ["/api/v1/users/octocat"] = { 200, USER },
    ["/api/v1/admin/users"] = {
      200,
      '[{"login":"octocat","id":1,"avatar_url":"","html_url":"http://localhost/octocat",'
        .. '"full_name":"The Octocat","email":"octocat@github.com","is_admin":false,'
        .. '"location":"","website":"","followers_count":100,"following_count":5,"created":"2011-01-25T18:44:36Z"}]',
    },
    ["/api/v1/user/followers"] = { 200, FOLLOWER },
    ["/api/v1/user/following"] = { 200, "[]" },
    ["/api/v1/user/following/hubot"] = { 204, nil },
    ["/api/v1/users/octocat/followers"] = { 200, FOLLOWER },
    ["/api/v1/users/octocat/following"] = { 200, "[]" },
    ["/api/v1/user/keys"] = {
      200,
      '[{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key","read_only":false,'
        .. '"created_at":"2020-01-01T00:00:00Z"}]',
    },
    ["/api/v1/user/keys/1"] = {
      200,
      '{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key","read_only":false,'
        .. '"created_at":"2020-01-01T00:00:00Z"}',
    },
    ["/api/v1/users/octocat/keys"] = {
      200,
      '[{"id":1,"key":"ssh-rsa AAAAB3N...","title":"my key","read_only":false,'
        .. '"created_at":"2020-01-01T00:00:00Z"}]',
    },
    ["/api/v1/user/gpg_keys"] = { 200, "[]" },
    ["/api/v1/users/octocat/gpg_keys"] = { 200, "[]" },
    ["/api/v1/user/emails"] = {
      200,
      '[{"email":"octocat@github.com","verified":true,"primary":true},'
        .. '{"email":"private@example.com","verified":false,"primary":false}]',
    },

    -- Teams
    ["/api/v1/user/teams"] = {
      200,
      '[{"id":1,"name":"core","description":"Core team","permission":"write",'
        .. '"includes_all_repositories":false,"units":["repo.code"]}]',
    },
    ["/api/v1/orgs/testorg/teams"] = {
      200,
      '[{"id":1,"name":"core","description":"Core team","permission":"write",'
        .. '"includes_all_repositories":false,"units":["repo.code"]},'
        .. '{"id":2,"name":"Owners","description":"","permission":"owner",'
        .. '"includes_all_repositories":true,"units":["repo.code"]}]',
    },
    ["/api/v1/orgs/testorg/teams?limit=50"] = {
      200,
      '[{"id":1,"name":"core","description":"Core team","permission":"write",'
        .. '"includes_all_repositories":false,"units":["repo.code"]},'
        .. '{"id":2,"name":"Owners","description":"","permission":"owner",'
        .. '"includes_all_repositories":true,"units":["repo.code"]}]',
    },
    ["/api/v1/teams/1"] = {
      200,
      '{"id":1,"name":"core","description":"Core team","permission":"write",'
        .. '"includes_all_repositories":false,"units":["repo.code"]}',
    },
    ["GET /api/v1/teams/1/members/octocat"] = { 204, nil },
    ["/api/v1/teams/1/members"] = {
      200,
      '[{"login":"octocat","id":1,"avatar_url":"","html_url":"http://localhost/octocat",'
        .. '"full_name":"The Octocat","email":"octocat@github.com","is_admin":false,'
        .. '"location":"","website":"","followers_count":0,"following_count":0,'
        .. '"created":"2011-01-25T18:44:36Z"}]',
    },
    ["/api/v1/teams/1/repos"] = {
      200,
      '[{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,'
        .. '"owner":{"login":"octocat","id":1,"avatar_url":"","url":"","html_url":"","type":"User"},'
        .. '"html_url":"http://localhost/octocat/hello-world","description":"My first repo",'
        .. '"fork":false,"url":"","clone_url":"","homepage":"","stargazers_count":0,'
        .. '"watchers_count":0,"language":null,"has_issues":true,"has_wiki":true,'
        .. '"forks_count":0,"archived":false,"open_issues_count":0,"default_branch":"main",'
        .. '"visibility":"public"}]',
    },
    ["GET /api/v1/teams/1/repos/testorg/hello-world"] = { 204, nil },
  }

  local entry = routes[method .. " " .. path] or routes[path]
  if entry then
    local status, body = entry[1], entry[2]
    SetStatus(status, status == 200 and "OK" or "No Content")
    if body then
      json(body)
    end
  elseif path:find("^/api/v1/repos/octocat/hello%-world/contents/") then
    local file = path:match("^/api/v1/repos/octocat/hello%-world/contents/(.+)$") or "file"
    SetStatus(200, "OK")
    json(
      '{"name":"'
        .. file
        .. '","path":"'
        .. file
        .. '","sha":"abc123","size":100,'
        .. '"type":"file","encoding":"base64","content":"SGVsbG8gV29ybGQ="}'
    )
  else
    SetStatus(404, "Not Found")
  end
end
