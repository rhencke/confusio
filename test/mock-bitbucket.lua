-- Mock Bitbucket server. Uses Bitbucket REST API v2 at /2.0/.
-- confusio translates Bitbucket responses to GitHub format.
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

  local REPO = '{"uuid":"{1234}","slug":"hello-world","name":"Hello-World",'
    .. '"full_name":"octocat/hello-world","is_private":false,'
    .. '"owner":{"nickname":"octocat","display_name":"Octocat","uuid":"{5678}",'
    .. '"type":"user","links":{"avatar":{"href":"https://example.com/avatar"},'
    .. '"html":{"href":"https://bitbucket.org/octocat"}}},'
    .. '"mainbranch":{"name":"main"},'
    .. '"links":{"html":{"href":"https://bitbucket.org/octocat/hello-world"},'
    .. '"self":{"href":"https://api.bitbucket.org/2.0/repositories/octocat/hello-world"}},'
    .. '"description":"My first repo","language":"JavaScript",'
    .. '"has_issues":true,"has_wiki":true,"size":12345,'
    .. '"created_on":"2011-01-26T19:01:12Z","updated_on":"2011-01-26T19:14:43Z",'
    .. '"forks":[]}'

  local rb = "/2.0/repositories/octocat/hello-world"
  local method = GetMethod()

  local SNIPPET = '{"id":"pHANT4","title":"Hello snippet",'
    .. '"is_private":false,'
    .. '"created_on":"2011-01-26T19:01:12Z",'
    .. '"updated_on":"2011-01-26T19:14:43Z",'
    .. '"owner":{"nickname":"octocat","display_name":"Octocat","uuid":"{5678}",'
    .. '"type":"user","links":{"avatar":{"href":"https://example.com/avatar"}}},'
    .. '"files":{"hello.txt":{"mimetype":"text/plain","size":11,'
    .. '"links":{"self":{"href":"https://api.bitbucket.org/2.0/snippets/octocat/pHANT4/files/hello.txt"}}}},'
    .. '"links":{"html":{"href":"https://bitbucket.org/snippets/octocat/pHANT4"}}}'
  local SNIPPET_COMMENT = '{"id":1,"created_on":"2011-01-26T19:01:12Z",'
    .. '"updated_on":"2011-01-26T19:14:43Z",'
    .. '"content":{"raw":"A comment","markup":"markdown","html":"<p>A comment</p>"},'
    .. '"author":{"nickname":"octocat","display_name":"Octocat","uuid":"{5678}",'
    .. '"type":"user","links":{"avatar":{"href":"https://example.com/avatar"}}}}'
  local SNIPPET_COMMIT = '{"hash":"deadbeef1234","date":"2011-01-26T19:01:12Z",'
    .. '"message":"Initial","author":{"raw":"Octocat <octocat@example.com>",'
    .. '"user":{"nickname":"octocat","display_name":"Octocat","uuid":"{5678}",'
    .. '"type":"user","links":{"avatar":{"href":""}}}}}'
  local ss = "/2.0/snippets"
  local sp = ss .. "/octocat/pHANT4"

  if path == "/2.0/user" then
    SetStatus(200, "OK")
    json('{"uuid":"{user1}","nickname":"octocat","display_name":"Octocat"}')

  -- Repo -------------------------------------------------------------------
  elseif path == rb then
    SetStatus(200, "OK")
    json(REPO)
  elseif path == "/2.0/repositories" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == "/2.0/repositories/testorg" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == "/2.0/repositories/octocat" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"pagelen":30,"size":1,"page":1}')

  -- Tags -------------------------------------------------------------------
  elseif path == rb .. "/refs/tags" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"name":"v1.0","target":{"hash":"abc123def456","type":"commit"}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Branches ---------------------------------------------------------------
  elseif path == rb .. "/refs/branches/main" then
    SetStatus(200, "OK")
    json('{"name":"main","target":{"hash":"abc123def456","type":"commit"},"type":"branch"}')
  elseif path == rb .. "/refs/branches/feature" and GetMethod() == "DELETE" then
    SetStatus(204, "No Content")
  elseif path == rb .. "/refs/branches" and GetMethod() == "POST" then
    SetStatus(201, "Created")
    json('{"name":"feature","target":{"hash":"abc123def456","type":"commit"},"type":"branch"}')
  elseif path == rb .. "/refs/branches" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"name":"main","target":{"hash":"abc123def456","type":"commit"},'
        .. '"type":"branch"}],"pagelen":30,"size":1,"page":1}'
    )

  -- Git database -----------------------------------------------------------
  elseif path == rb .. "/refs" then
    -- list_git_matching_refs with no heads/tags prefix (q param ignored in mock)
    SetStatus(200, "OK")
    json(
      '{"values":[{"name":"main","target":{"hash":"abc123def456","type":"commit"},'
        .. '"type":"branch"}],"pagelen":30,"size":1,"page":1}'
    )

  -- Commits ----------------------------------------------------------------
  elseif path == rb .. "/commit/abc123" then
    SetStatus(200, "OK")
    json(
      '{"hash":"abc123def456","message":"Initial commit","date":"2011-01-26T19:01:12Z",'
        .. '"author":{"raw":"Octocat <octocat@example.com>",'
        .. '"user":{"display_name":"Octocat","nickname":"octocat"}},'
        .. '"parents":[]}'
    )
  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"hash":"abc123def456","message":"Initial commit",'
        .. '"date":"2011-01-26T19:01:12Z",'
        .. '"author":{"raw":"Octocat","user":{"display_name":"Octocat","nickname":"octocat"}},'
        .. '"parents":[]}],"pagelen":30,"size":1,"page":1}'
    )

  -- Commit statuses --------------------------------------------------------
  elseif path == rb .. "/commit/abc123/statuses/build" and GetMethod() == "POST" then
    SetStatus(200, "OK")
    json(
      '{"state":"INPROGRESS","key":"ci/test","description":"Build started",'
        .. '"url":"https://ci.example.com/build/1",'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-01T00:00:00Z"}'
    )
  elseif path == rb .. "/commit/abc123/statuses" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"state":"SUCCESSFUL","key":"ci","description":"Build passed",'
        .. '"url":"http://ci.example.com","created_on":"2020-01-01T00:00:00Z",'
        .. '"updated_on":"2020-01-01T00:00:00Z"}],"pagelen":30,"size":1,"page":1}'
    )

  -- Contents ---------------------------------------------------------------
  elseif path == rb .. "/src/main/README.md" or path == rb .. "/src/HEAD/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")
  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/src/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Forks ------------------------------------------------------------------
  elseif path == rb .. "/forks" then
    SetStatus(200, "OK")
    json('{"values":[],"pagelen":30,"size":0,"page":1}')

  -- Deploy keys ------------------------------------------------------------
  elseif path == rb .. "/deploy-keys/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"key":"ssh-rsa AAAAB3...","label":"my key",'
        .. '"created_on":"2020-01-01T00:00:00Z"}'
    )
  elseif path == rb .. "/deploy-keys" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"key":"ssh-rsa AAAAB3...","label":"my key",'
        .. '"created_on":"2020-01-01T00:00:00Z"}],"pagelen":30,"size":1,"page":1}'
    )

  -- Webhooks ---------------------------------------------------------------
  elseif path == rb .. "/hooks/{1}" then
    SetStatus(200, "OK")
    json('{"uuid":"{1}","url":"https://example.com/hook","events":["repo:push"],"active":true}')
  elseif path == rb .. "/hooks" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"uuid":"{1}","url":"https://example.com/hook",'
        .. '"events":["repo:push"],"active":true}],"pagelen":30,"size":1,"page":1}'
    )

  -- Issues -----------------------------------------------------------------
  elseif path == rb .. "/issues/9999" then
    SetStatus(404, "Not Found")
    json('{"type":"error","error":{"message":"Issue #9999 does not exist"}}')
  elseif path == rb .. "/issues/1/comments" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"content":{"raw":"This is a comment"},'
        .. '"author":{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
        .. '"links":{"avatar":{"href":""},"html":{"href":""}}},'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-01T00:00:00Z",'
        .. '"links":{"html":{"href":""}}}],"pagelen":30,"size":1,"page":1}'
    )
  elseif path == rb .. "/issues/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"title":"Found a bug","content":{"raw":"Bug description"},'
        .. '"state":"open","priority":"major","kind":"bug",'
        .. '"reporter":{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
        .. '"type":"user","links":{"avatar":{"href":""},"html":{"href":""}}},'
        .. '"assignee":null,'
        .. '"milestone":{"id":1,"name":"v1.0"},'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-02T00:00:00Z",'
        .. '"links":{"html":{"href":"http://bitbucket.org/octocat/hello-world/issues/1"}}}'
    )
  elseif path == rb .. "/issues" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"title":"Found a bug","content":{"raw":"Bug description"},'
        .. '"state":"open","priority":"major","kind":"bug",'
        .. '"reporter":{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
        .. '"type":"user","links":{"avatar":{"href":""},"html":{"href":""}}},'
        .. '"assignee":null,'
        .. '"milestone":{"id":1,"name":"v1.0"},'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-02T00:00:00Z",'
        .. '"links":{"html":{"href":"http://bitbucket.org/octocat/hello-world/issues/1"}}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Pull Requests ----------------------------------------------------------
  elseif path == rb .. "/pullrequests" then
    SetStatus(200, "OK")
    local BB_USER = '{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
      .. '"uuid":"{5678}","type":"user",'
      .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}'
    local PR = '{"id":1,"title":"A great PR","description":"PR description",'
      .. '"state":"MERGED",'
      .. '"author":'
      .. BB_USER
      .. ","
      .. '"source":{"branch":{"name":"feature"},"commit":{"hash":"abc123"},'
      .. '"repository":{"full_name":"octocat/hello-world"}},'
      .. '"destination":{"branch":{"name":"main"},"commit":{"hash":"def456"},'
      .. '"repository":{"full_name":"octocat/hello-world"}},'
      .. '"merge_commit":{"hash":"merged123"},'
      .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-03T00:00:00Z",'
      .. '"participants":[{"user":'
      .. BB_USER
      .. ',"role":"REVIEWER","approved":true,'
      .. '"state":"approved","participated_on":"2020-01-02T00:00:00Z"}],'
      .. '"links":{"html":{"href":"https://bitbucket.org/octocat/hello-world/pull-requests/1"},'
      .. '"self":{"href":"https://api.bitbucket.org/2.0/repositories/octocat/hello-world/pullrequests/1"},'
      .. '"diff":{"href":"https://api.bitbucket.org/2.0/repositories/octocat/hello-world/pullrequests/1/diff"}}}'
    json('{"values":[' .. PR .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == rb .. "/pullrequests/1" then
    SetStatus(200, "OK")
    local BB_USER = '{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
      .. '"uuid":"{5678}","type":"user",'
      .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}'
    json(
      '{"id":1,"title":"A great PR","description":"PR description",'
        .. '"state":"MERGED",'
        .. '"author":'
        .. BB_USER
        .. ","
        .. '"source":{"branch":{"name":"feature"},"commit":{"hash":"abc123"},'
        .. '"repository":{"full_name":"octocat/hello-world"}},'
        .. '"destination":{"branch":{"name":"main"},"commit":{"hash":"def456"},'
        .. '"repository":{"full_name":"octocat/hello-world"}},'
        .. '"merge_commit":{"hash":"merged123"},'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-03T00:00:00Z",'
        .. '"participants":[{"user":'
        .. BB_USER
        .. ',"role":"REVIEWER","approved":true,'
        .. '"state":"approved","participated_on":"2020-01-02T00:00:00Z"}],'
        .. '"links":{"html":{"href":"https://bitbucket.org/octocat/hello-world/pull-requests/1"},'
        .. '"self":{"href":"https://api.bitbucket.org/2.0/repositories/octocat/hello-world/pullrequests/1"},'
        .. '"diff":{"href":"https://api.bitbucket.org/2.0/repositories/octocat/hello-world/pullrequests/1/diff"}}}'
    )
  elseif path == rb .. "/pullrequests/1/commits" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"hash":"abc123def456","message":"Initial commit",'
        .. '"date":"2011-01-26T19:01:12Z",'
        .. '"author":{"raw":"Octocat","user":{"display_name":"Octocat","nickname":"octocat"}},'
        .. '"parents":[]}],"pagelen":30,"size":1,"page":1}'
    )
  elseif path == rb .. "/pullrequests/1/diffstat" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"type":"diffstat","status":"modified","lines_added":2,"lines_removed":1,'
        .. '"old":{"type":"commit_file","path":"README.md"},'
        .. '"new":{"type":"commit_file","path":"README.md"}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )
  elseif path == rb .. "/pullrequests/1/merge" then
    SetStatus(200, "OK")
    local BB_USER = '{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
      .. '"uuid":"{5678}","type":"user",'
      .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}'
    json(
      '{"id":1,"title":"A great PR","state":"MERGED",'
        .. '"author":'
        .. BB_USER
        .. ","
        .. '"source":{"branch":{"name":"feature"},"commit":{"hash":"abc123"},'
        .. '"repository":{"full_name":"octocat/hello-world"}},'
        .. '"destination":{"branch":{"name":"main"},"commit":{"hash":"def456"},'
        .. '"repository":{"full_name":"octocat/hello-world"}},'
        .. '"merge_commit":{"hash":"merged123"},'
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-03T00:00:00Z",'
        .. '"participants":[],'
        .. '"links":{"html":{"href":"https://bitbucket.org/octocat/hello-world/pull-requests/1"}}}'
    )
  elseif path == rb .. "/pullrequests/1/comments" then
    SetStatus(200, "OK")
    local BB_USER = '{"nickname":"octocat","display_name":"The Octocat","account_id":"abc123",'
      .. '"uuid":"{5678}","type":"user",'
      .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}'
    json(
      '{"values":[{"id":1,"content":{"raw":"Nice change here"},'
        .. '"author":'
        .. BB_USER
        .. ","
        .. '"created_on":"2020-01-01T00:00:00Z","updated_on":"2020-01-01T00:00:00Z",'
        .. '"inline":{"path":"README.md","from":null,"to":1},'
        .. '"links":{"html":{"href":""}}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Milestones --------------------------------------------------------------
  elseif path == rb .. "/milestones" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"name":"v1.0","resource_uri":"/api/2.0/repositories/octocat/hello-world/milestones/1"}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Activity: watchers (used for both stargazers and subscribers) -----------
  elseif path == rb .. "/watchers" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"account_id":"abc123","nickname":"octocat","display_name":"The Octocat",'
        .. '"links":{"avatar":{"href":""},"html":{"href":"http://bitbucket.org/octocat"}}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Users ------------------------------------------------------------------
  elseif path == "/2.0/user" then
    SetStatus(200, "OK")
    json(
      '{"account_id":"abc123","nickname":"octocat","display_name":"The Octocat",'
        .. '"links":{"avatar":{"href":""},"html":{"href":"http://bitbucket.org/octocat"}}}'
    )
  elseif path == "/2.0/users/octocat" then
    SetStatus(200, "OK")
    json(
      '{"account_id":"abc123","nickname":"octocat","display_name":"The Octocat",'
        .. '"links":{"avatar":{"href":""},"html":{"href":"http://bitbucket.org/octocat"}}}'
    )

  -- Workspaces ----------------------------------------------------------------
  elseif path == "/2.0/workspaces/octocat" then
    SetStatus(200, "OK")
    json(
      '{"uuid":"{5678}","slug":"octocat","name":"Octocat","type":"workspace",'
        .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}'
    )
  elseif path == "/2.0/workspaces" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"uuid":"{5678}","slug":"octocat","name":"Octocat","type":"workspace",'
        .. '"links":{"avatar":{"href":""},"html":{"href":"https://bitbucket.org/octocat"}}}],'
        .. '"pagelen":30,"size":1,"page":1}'
    )

  -- Interactions --------------------------------------------------------------
  -- Bitbucket has no native GitHub Interactions API; confusio returns stubs directly.
  -- These routes document what the backend would return if ever proxied.
  elseif
    (
      path == "/orgs/testorg/interaction-limits"
      or path == "/repos/octocat/hello-world/interaction-limits"
      or path == "/user/interaction-limits"
    ) and (GetMethod() == "GET" or GetMethod() == "PUT" or GetMethod() == "DELETE")
  then
    SetStatus(404, "Not Found")

  -- Migrations ----------------------------------------------------------------
  -- Bitbucket Cloud has no GitHub-style org/user migration API; confusio returns
  -- fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")

  -- Snippets (Gists) ----------------------------------------------------------
  elseif (path == ss or path:find("^" .. ss .. "%?")) and method == "GET" then
    SetStatus(200, "OK")
    json('{"values":[' .. SNIPPET .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == ss and method == "POST" then
    SetStatus(201, "Created")
    json(SNIPPET)
  elseif (path == ss .. "/octocat" or path:find("^" .. ss .. "/octocat%?")) and method == "GET" then
    SetStatus(200, "OK")
    json('{"values":[' .. SNIPPET .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == sp and method == "GET" then
    SetStatus(200, "OK")
    json(SNIPPET)
  elseif path == sp and method == "PUT" then
    SetStatus(200, "OK")
    json(SNIPPET)
  elseif path == sp and method == "DELETE" then
    SetStatus(204, "No Content")
  elseif
    (path == sp .. "/comments" or path:find("^" .. sp:gsub("%-", "%%-") .. "/comments%?"))
    and method == "GET"
  then
    SetStatus(200, "OK")
    json('{"values":[' .. SNIPPET_COMMENT .. '],"pagelen":30,"size":1,"page":1}')
  elseif path == sp .. "/comments" and method == "POST" then
    SetStatus(201, "Created")
    json(SNIPPET_COMMENT)
  elseif path == sp .. "/comments/1" and method == "GET" then
    SetStatus(200, "OK")
    json(SNIPPET_COMMENT)
  elseif path == sp .. "/comments/1" and method == "PUT" then
    SetStatus(200, "OK")
    json(SNIPPET_COMMENT)
  elseif path == sp .. "/comments/1" and method == "DELETE" then
    SetStatus(204, "No Content")
  elseif
    (path == sp .. "/commits" or path:find("^" .. sp:gsub("%-", "%%-") .. "/commits%?"))
    and method == "GET"
  then
    SetStatus(200, "OK")
    json('{"values":[' .. SNIPPET_COMMIT .. '],"pagelen":30,"size":1,"page":1}')
  elseif
    (path == sp .. "/forks" or path:find("^" .. sp:gsub("%-", "%%-") .. "/forks%?"))
    and method == "GET"
  then
    SetStatus(200, "OK")
    json('{"values":[],"pagelen":30,"size":0,"page":1}')
  elseif path == sp .. "/watch" and method == "GET" then
    SetStatus(204, "No Content")
  elseif path == sp .. "/watch" and method == "PUT" then
    SetStatus(204, "No Content")
  elseif path == sp .. "/watch" and method == "DELETE" then
    SetStatus(204, "No Content")
  elseif path == sp .. "/deadbeef1234" and method == "GET" then
    SetStatus(200, "OK")
    json(SNIPPET)
  else
    SetStatus(404, "Not Found")
  end
end
