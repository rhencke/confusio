-- Mock Bitbucket server. Uses Bitbucket REST API v2 at /2.0/.
-- confusio translates Bitbucket responses to GitHub format.
function OnHttpRequest()
  local path = GetPath()
  local method = GetMethod()

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
  elseif path == rb .. "/refs/branches" then
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

  -- Milestones --------------------------------------------------------------
  elseif path == rb .. "/milestones" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"name":"v1.0","resource_uri":"/api/2.0/repositories/octocat/hello-world/milestones/1"}],'
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
  else
    SetStatus(404, "Not Found")
  end
end
