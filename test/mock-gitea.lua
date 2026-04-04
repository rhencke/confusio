function OnHttpRequest()
  local path = GetPath()
  local auth = GetHeader("Authorization")
  if auth ~= nil and auth ~= "token testtoken" then
    SetStatus(401, "Unauthorized")
    return
  end

  if path == "/api/v1/version" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('{"version":"1.20.0"}')

  elseif path == "/api/v1/repos/octocat/hello-world" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
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
    SetHeader("Content-Type", "application/json")
    Write('[{"id":1,"name":"hello-world","full_name":"octocat/hello-world","private":false,' ..
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
    SetHeader("Content-Type", "application/json")
    Write('[{"id":2,"name":"org-repo","full_name":"testorg/org-repo","private":false,' ..
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
    SetHeader("Content-Type", "application/json")
    Write('{"topics":["lua","api"]}')

  elseif path == "/api/v1/repos/octocat/hello-world/languages" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('{"JavaScript":12345,"Lua":6789}')

  elseif path == "/api/v1/repos/octocat/hello-world/contributors" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('[{"login":"octocat","id":1,"contributions":100}]')

  elseif path == "/api/v1/repos/octocat/hello-world/tags" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('[{"name":"v1.0","id":"abc123","message":"","commit":{"sha":"abc123def456","url":""}}]')

  else
    SetStatus(404, "Not Found")
  end
end
