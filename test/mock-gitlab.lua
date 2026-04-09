function OnHttpRequest()
  local path = GetPath()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  -- Redbean's Fetch decodes %2F to / before sending, so the mock receives plain slashes
  local pb = "/api/v4/projects/octocat/hello-world"

  -- Minimal GitLab project object
  local PROJECT = '{"id":1,"path":"hello-world","path_with_namespace":"octocat/hello-world",'
    .. '"namespace":{"id":1,"path":"octocat","name":"octocat","kind":"user","avatar_url":"",'
    .. '"web_url":"http://localhost/octocat"},'
    .. '"visibility":"public","web_url":"http://localhost/octocat/hello-world",'
    .. '"description":"My first repo","forked_from_project":null,'
    .. '"http_url_to_repo":"http://localhost/octocat/hello-world.git",'
    .. '"ssh_url_to_repo":"git@localhost:octocat/hello-world.git",'
    .. '"statistics":{"repository_size":12345},"star_count":80,"forks_count":9,'
    .. '"open_issues_count":0,"issues_enabled":true,"wiki_enabled":false,'
    .. '"archived":false,"default_branch":"main",'
    .. '"created_at":"2011-01-26T19:01:12Z","last_activity_at":"2011-01-26T19:14:43Z",'
    .. '"topics":["lua","api"],'
    .. '"license":{"key":"mit","name":"MIT License"}}'

  if path == "/api/v4/version" then
    SetStatus(200, "OK")
    json('{"version":"16.0.0","revision":"abc123"}')

  -- Project ----------------------------------------------------------------
  elseif path == pb then
    SetStatus(200, "OK")
    json(PROJECT)
  elseif path == "/api/v4/projects" then
    -- get_user_repos (?owned=true&membership=true) and get_repositories (?visibility=public)
    SetStatus(200, "OK")
    json("[" .. PROJECT .. "]")
  elseif path == "/api/v4/groups/testorg/projects" then
    SetStatus(200, "OK")
    json("[" .. PROJECT .. "]")

  -- Languages --------------------------------------------------------------
  elseif path == pb .. "/languages" then
    SetStatus(200, "OK")
    json('{"JavaScript":66.69,"Lua":33.31}')

  -- Contributors -----------------------------------------------------------
  elseif path == pb .. "/repository/contributors" then
    SetStatus(200, "OK")
    json('[{"name":"octocat","email":"octocat@github.com","commits":100}]')

  -- Git database blobs -----------------------------------------------------
  elseif path == pb .. "/repository/blobs/3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15" then
    SetStatus(200, "OK")
    json(
      '{"size":19,"encoding":"base64","content":"Q29udGVudCBvZiBibG9i\\n",'
        .. '"sha":"3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15"}'
    )

  -- Tags -------------------------------------------------------------------
  elseif path == pb .. "/repository/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","commit":{"id":"abc123def456","message":"Release"}}]')

  -- Branches ---------------------------------------------------------------
  elseif path == pb .. "/repository/branches/main" then
    SetStatus(200, "OK")
    json(
      '{"name":"main","commit":{"id":"abc123def456","message":"Initial commit"},"protected":false}'
    )
  elseif path == pb .. "/repository/branches" then
    SetStatus(200, "OK")
    json(
      '[{"name":"main","commit":{"id":"abc123def456","message":"Initial commit"},"protected":false}]'
    )

  -- Commits ----------------------------------------------------------------
  elseif path == pb .. "/repository/commits/abc123/statuses" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"status":"success","description":"Build passed","name":"ci",'
        .. '"target_url":"http://ci.example.com","created_at":"2020-01-01T00:00:00Z",'
        .. '"updated_at":"2020-01-01T00:00:00Z"}]'
    )
  elseif path == "/api/v4/projects/octocat/hello-world/statuses/abc123" then
    -- POST /projects/{id}/statuses/{sha} — used by post_check_runs
    SetStatus(201, "Created")
    json(
      '{"id":2,"status":"running","description":"Build started","name":"ci/test",'
        .. '"target_url":"https://ci.example.com/build/1","created_at":"2020-01-01T00:00:00Z",'
        .. '"updated_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/repository/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '{"id":"abc123def456","message":"Initial commit","author_name":"Octocat",'
        .. '"author_email":"octocat@github.com","authored_date":"2011-01-26T19:01:12Z",'
        .. '"web_url":"http://localhost/octocat/hello-world/-/commit/abc123def456"}'
    )
  elseif path == pb .. "/repository/commits" then
    SetStatus(200, "OK")
    json(
      '[{"id":"abc123def456","message":"Initial commit","author_name":"Octocat",'
        .. '"author_email":"octocat@github.com","authored_date":"2011-01-26T19:01:12Z",'
        .. '"web_url":"http://localhost/octocat/hello-world/-/commit/abc123def456"}]'
    )

  -- Contents ---------------------------------------------------------------
  elseif path == pb .. "/repository/files/README.md" then
    SetStatus(200, "OK")
    json(
      '{"file_name":"README.md","file_path":"README.md","blob_id":"abc123",'
        .. '"size":100,"encoding":"base64","content":"SGVsbG8gV29ybGQ="}'
    )

  -- Compare ----------------------------------------------------------------
  elseif path == pb .. "/repository/compare" then
    SetStatus(200, "OK")
    json('{"commits":[],"diffs":[],"compare_timeout":false}')

  -- Collaborators ----------------------------------------------------------
  elseif path == pb .. "/members/all" then
    SetStatus(200, "OK")
    json('[{"id":1,"username":"octocat","avatar_url":"","access_level":50}]')
  elseif path == "/api/v4/users" then
    SetStatus(200, "OK")
    json('[{"id":1,"username":"octocat","avatar_url":""}]')
  elseif path == pb .. "/members/1" then
    SetStatus(200, "OK")
    json('{"id":1,"username":"octocat","access_level":50}')

  -- Forks ------------------------------------------------------------------
  elseif path == pb .. "/forks" then
    SetStatus(200, "OK")
    json(
      '[{"id":3,"path":"hello-world","path_with_namespace":"forker/hello-world",'
        .. '"namespace":{"id":2,"path":"forker","name":"forker","kind":"user","avatar_url":"",'
        .. '"web_url":"http://localhost/forker"},'
        .. '"visibility":"public","web_url":"http://localhost/forker/hello-world",'
        .. '"description":"Fork","forked_from_project":{"id":1},'
        .. '"http_url_to_repo":"http://localhost/forker/hello-world.git",'
        .. '"ssh_url_to_repo":"git@localhost:forker/hello-world.git",'
        .. '"star_count":0,"forks_count":0,"open_issues_count":0,'
        .. '"issues_enabled":true,"wiki_enabled":false,"archived":false,"default_branch":"main",'
        .. '"created_at":"2020-01-01T00:00:00Z","last_activity_at":"2020-01-01T00:00:00Z","topics":[]}]'
    )

  -- Releases ---------------------------------------------------------------
  elseif path == pb .. "/releases/permalink/latest" then
    SetStatus(200, "OK")
    json(
      '{"tag_name":"v1.0","name":"Release 1.0","description":"First release",'
        .. '"created_at":"2020-01-01T00:00:00Z","released_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/releases/v1.0/assets/links/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"name":"binary.zip","url":"http://localhost/attachments/1",'
        .. '"link_type":"other","created_at":"2020-01-01T00:00:00Z",'
        .. '"updated_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/releases/v1.0/assets/links" then
    if GetMethod() == "POST" then
      SetStatus(201, "Created")
      json(
        '{"id":2,"name":"new-asset.zip","url":"http://localhost/new",'
          .. '"link_type":"other","created_at":"2020-01-01T00:00:00Z",'
          .. '"updated_at":"2020-01-01T00:00:00Z"}'
      )
    else
      SetStatus(200, "OK")
      json(
        '[{"id":1,"name":"binary.zip","url":"http://localhost/attachments/1",'
          .. '"link_type":"other","created_at":"2020-01-01T00:00:00Z",'
          .. '"updated_at":"2020-01-01T00:00:00Z"}]'
      )
    end
  elseif path == pb .. "/releases/v1.0" then
    SetStatus(200, "OK")
    json(
      '{"tag_name":"v1.0","name":"Release 1.0","description":"First release",'
        .. '"created_at":"2020-01-01T00:00:00Z","released_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/releases" then
    SetStatus(200, "OK")
    json(
      '[{"tag_name":"v1.0","name":"Release 1.0","description":"First release",'
        .. '"created_at":"2020-01-01T00:00:00Z","released_at":"2020-01-01T00:00:00Z"}]'
    )

  -- Deploy keys ------------------------------------------------------------
  elseif path == pb .. "/deploy_keys/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"title":"my key","key":"ssh-rsa AAAAB3...","can_push":false,'
        .. '"created_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/deploy_keys" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"title":"my key","key":"ssh-rsa AAAAB3...","can_push":false,'
        .. '"created_at":"2020-01-01T00:00:00Z"}]'
    )

  -- Webhooks ---------------------------------------------------------------
  elseif path == pb .. "/hooks/1" then
    SetStatus(200, "OK")
    json('{"id":1,"url":"https://example.com/hook","push_events":true,"active":true}')
  elseif path == pb .. "/hooks" then
    SetStatus(200, "OK")
    json('[{"id":1,"url":"https://example.com/hook","push_events":true,"active":true}]')

  -- Commit comments --------------------------------------------------------
  elseif path == pb .. "/repository/commits/abc123/comments" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"note":"Nice commit","author":{"username":"octocat"},'
        .. '"created_at":"2020-01-01T00:00:00Z"}]'
    )

  -- Users' repos -----------------------------------------------------------
  elseif path == "/api/v4/users/octocat/projects" then
    SetStatus(200, "OK")
    json("[" .. PROJECT .. "]")

  -- Users ------------------------------------------------------------------
  elseif path == "/api/v4/user" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"username":"octocat","name":"The Octocat","email":"octocat@github.com",'
        .. '"avatar_url":"","web_url":"http://localhost/octocat","is_admin":false,'
        .. '"location":"San Francisco","website_url":"https://github.blog","created_at":"2011-01-25T18:44:36Z"}'
    )
  elseif path == "/api/v4/users" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"username":"octocat","name":"The Octocat","email":"octocat@github.com",'
        .. '"avatar_url":"","web_url":"http://localhost/octocat","is_admin":false,'
        .. '"location":"San Francisco","website_url":"https://github.blog","created_at":"2011-01-25T18:44:36Z"}]'
    )
  elseif path == "/api/v4/user/emails" then
    SetStatus(200, "OK")
    json('[{"id":1,"email":"octocat@github.com","confirmed_at":"2011-01-25T18:44:36Z"}]')
  elseif path == "/api/v4/user/keys" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"title":"my key","key":"ssh-rsa AAAAB3N...","created_at":"2020-01-01T00:00:00Z"}]'
    )
  elseif path == "/api/v4/user/keys/1" then
    SetStatus(200, "OK")
    json('{"id":1,"title":"my key","key":"ssh-rsa AAAAB3N...","created_at":"2020-01-01T00:00:00Z"}')
  elseif path == "/api/v4/users/1/keys" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"title":"my key","key":"ssh-rsa AAAAB3N...","created_at":"2020-01-01T00:00:00Z"}]'
    )
  elseif path == "/api/v4/user/gpg_keys" then
    SetStatus(200, "OK")
    json("[]")
  elseif path == "/api/v4/users/1/gpg_keys" then
    SetStatus(200, "OK")
    json("[]")

  -- Teams (subgroups) ---------------------------------------------------------
  elseif path == "/api/v4/groups/testorg/subgroups" then
    SetStatus(200, "OK")
    json(
      '[{"id":10,"name":"core","path":"core","description":"Core team",'
        .. '"visibility":"internal","web_url":"http://localhost/testorg/core"}]'
    )

  -- Redbean decodes %2F → / before calling GetPath(), so match decoded form.
  elseif path == "/api/v4/groups/testorg/core" then
    SetStatus(200, "OK")
    json(
      '{"id":10,"name":"core","path":"core","description":"Core team",'
        .. '"visibility":"internal","web_url":"http://localhost/testorg/core"}'
    )
  elseif path == "/api/v4/groups/10/members" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
        .. '"web_url":"http://localhost/octocat","access_level":30}]'
    )
  elseif path == "/api/v4/groups/10/members/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"username":"octocat","name":"The Octocat","access_level":30,'
        .. '"avatar_url":"","web_url":"http://localhost/octocat"}'
    )
  elseif path == "/api/v4/groups/10/projects" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"name":"hello-world","path":"hello-world",'
        .. '"path_with_namespace":"octocat/hello-world","description":"My first repo",'
        .. '"visibility":"public","web_url":"http://localhost/octocat/hello-world",'
        .. '"ssh_url_to_repo":"git@localhost:octocat/hello-world.git",'
        .. '"http_url_to_repo":"http://localhost/octocat/hello-world.git",'
        .. '"forks_count":0,"star_count":0,"default_branch":"main",'
        .. '"namespace":{"id":10,"kind":"group","path":"core","name":"core"}}]'
    )
  elseif path == "/api/v4/groups/10/subgroups" then
    SetStatus(200, "OK")
    json("[]")

  -- Legacy team-by-id API -------------------------------------------------------
  -- Project owned by group 10 (used for GET /teams/{team_id}/repos/{owner}/{repo})
  elseif path == "/api/v4/projects/testorg/core-project" then
    SetStatus(200, "OK")
    json(
      '{"id":2,"path":"core-project","path_with_namespace":"testorg/core-project",'
        .. '"namespace":{"id":10,"path":"core","name":"core","kind":"group","avatar_url":"",'
        .. '"web_url":"http://localhost/testorg/core"},'
        .. '"visibility":"public","web_url":"http://localhost/testorg/core-project",'
        .. '"description":"","forked_from_project":null,'
        .. '"http_url_to_repo":"http://localhost/testorg/core-project.git",'
        .. '"ssh_url_to_repo":"git@localhost:testorg/core-project.git",'
        .. '"statistics":{"repository_size":0},"star_count":0,"forks_count":0,'
        .. '"open_issues_count":0,"issues_enabled":true,"wiki_enabled":false,'
        .. '"archived":false,"default_branch":"main",'
        .. '"created_at":"2011-01-26T19:01:12Z","last_activity_at":"2011-01-26T19:01:12Z",'
        .. '"topics":[]}'
    )
  elseif path == "/api/v4/groups" then
    -- GET /user/teams: all groups the current user belongs to
    SetStatus(200, "OK")
    json(
      '[{"id":10,"name":"core","path":"core","description":"Core team",'
        .. '"visibility":"internal","web_url":"http://localhost/testorg/core"}]'
    )
  elseif path == "/api/v4/groups/10" then
    SetStatus(200, "OK")
    json(
      '{"id":10,"name":"core","path":"core","description":"Core team",'
        .. '"visibility":"internal","web_url":"http://localhost/testorg/core"}'
    )

  -- Merge Requests ---------------------------------------------------------
  elseif path == pb .. "/merge_requests" then
    SetStatus(200, "OK")
    local MR_USER = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    local MR = '{"id":1,"iid":1,"state":"opened","title":"A great PR",'
      .. '"description":"PR description",'
      .. '"source_branch":"feature","target_branch":"main",'
      .. '"author":'
      .. MR_USER
      .. ","
      .. '"draft":false,'
      .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-02T00:00:00Z",'
      .. '"closed_at":null,"merged_at":"2020-01-03T00:00:00Z",'
      .. '"merge_commit_sha":"abc123def456",'
      .. '"diff_refs":{"base_sha":"base123","head_sha":"head456","start_sha":"start789"},'
      .. '"merge_status":"can_be_merged","user_notes_count":0,"changes_count":"1",'
      .. '"web_url":"http://localhost/octocat/hello-world/-/merge_requests/1"}'
    json("[" .. MR .. "]")
  elseif path == pb .. "/merge_requests/1" then
    SetStatus(200, "OK")
    local MR_USER = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '{"id":1,"iid":1,"state":"opened","title":"A great PR",'
        .. '"description":"PR description",'
        .. '"source_branch":"feature","target_branch":"main",'
        .. '"author":'
        .. MR_USER
        .. ","
        .. '"draft":false,'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-02T00:00:00Z",'
        .. '"closed_at":null,"merged_at":"2020-01-03T00:00:00Z",'
        .. '"merge_commit_sha":"abc123def456",'
        .. '"diff_refs":{"base_sha":"base123","head_sha":"head456","start_sha":"start789"},'
        .. '"merge_status":"can_be_merged","user_notes_count":0,"changes_count":"1",'
        .. '"web_url":"http://localhost/octocat/hello-world/-/merge_requests/1"}'
    )
  elseif path == pb .. "/merge_requests/1/commits" then
    SetStatus(200, "OK")
    json("[]")
  elseif path == pb .. "/merge_requests/1/changes" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"iid":1,"changes":[{"old_path":"README.md","new_path":"README.md",'
        .. '"diff":"@@ -1 +1 @@\\n-old\\n+new","new_file":false,"deleted_file":false,'
        .. '"renamed_file":false}]}'
    )
  elseif path == pb .. "/merge_requests/1/approvals" then
    SetStatus(200, "OK")
    local MR_USER = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '{"approved_by":[{"user":'
        .. MR_USER
        .. '}],"approved":true,'
        .. '"created_at":"2020-01-01T00:00:00Z"}'
    )
  elseif path == pb .. "/merge_requests/1/reviewers" then
    SetStatus(200, "OK")
    local MR_USER = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json("[" .. MR_USER .. "]")
  elseif path == pb .. "/merge_requests/1/notes" then
    SetStatus(200, "OK")
    local MR_USER = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '[{"id":1,"body":"Nice change here","author":'
        .. MR_USER
        .. ","
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
        .. '"system":false,'
        .. '"position":{"new_path":"README.md","old_path":"README.md","new_line":1,'
        .. '"head_sha":"head456","base_sha":"base123"}}]'
    )

  -- Issues -----------------------------------------------------------------
  elseif path == pb .. "/issues" then
    SetStatus(200, "OK")
    local LABEL_OBJ =
      '{"id":1,"name":"bug","color":"#d73a4a","description":"Something is not working"}'
    local MILESTONE_OBJ = '{"id":1,"iid":1,"title":"v1.0","description":"First milestone","state":"active",'
      .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
      .. '"closed_at":null,"due_date":null}'
    local USER_OBJ = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '[{"id":1,"iid":1,"title":"Found a bug","description":"Bug description",'
        .. '"state":"opened","author":'
        .. USER_OBJ
        .. ',"assignees":[],'
        .. '"labels":['
        .. LABEL_OBJ
        .. '],"milestone":'
        .. MILESTONE_OBJ
        .. ","
        .. '"user_notes_count":1,'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-02T00:00:00Z",'
        .. '"closed_at":null,"web_url":"http://localhost/octocat/hello-world/-/issues/1"}]'
    )
  elseif path == pb .. "/issues/1" then
    SetStatus(200, "OK")
    local LABEL_OBJ =
      '{"id":1,"name":"bug","color":"#d73a4a","description":"Something is not working"}'
    local MILESTONE_OBJ = '{"id":1,"iid":1,"title":"v1.0","description":"First milestone","state":"active",'
      .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
      .. '"closed_at":null,"due_date":null}'
    local USER_OBJ = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '{"id":1,"iid":1,"title":"Found a bug","description":"Bug description",'
        .. '"state":"opened","author":'
        .. USER_OBJ
        .. ',"assignees":[],'
        .. '"labels":['
        .. LABEL_OBJ
        .. '],"milestone":'
        .. MILESTONE_OBJ
        .. ","
        .. '"user_notes_count":1,'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-02T00:00:00Z",'
        .. '"closed_at":null,"web_url":"http://localhost/octocat/hello-world/-/issues/1"}'
    )
  elseif path == pb .. "/issues/9999" then
    SetStatus(404, "Not Found")
    json('{"message":"404 Issue Not Found"}')
  elseif path == pb .. "/issues/1/notes" then
    SetStatus(200, "OK")
    local USER_OBJ = '{"id":1,"username":"octocat","name":"The Octocat","avatar_url":"",'
      .. '"web_url":"http://localhost/octocat"}'
    json(
      '[{"id":1,"body":"This is a comment","author":'
        .. USER_OBJ
        .. ","
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z"}]'
    )

  -- Labels -----------------------------------------------------------------
  elseif path == pb .. "/labels" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"bug","color":"#d73a4a","description":"Something is not working"}]')
  elseif path == pb .. "/labels/1" then
    SetStatus(200, "OK")
    json('{"id":1,"name":"bug","color":"#d73a4a","description":"Something is not working"}')

  -- Milestones -------------------------------------------------------------
  elseif path == pb .. "/milestones" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"iid":1,"title":"v1.0","description":"First milestone","state":"active",'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
        .. '"closed_at":null,"due_date":null}]'
    )
  elseif path == pb .. "/milestones/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"iid":1,"title":"v1.0","description":"First milestone","state":"active",'
        .. '"created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z",'
        .. '"closed_at":null,"due_date":null}'
    )
  -- Interactions --------------------------------------------------------------
  -- GitLab has no native GitHub Interactions API; confusio returns stubs directly.
  -- These routes document what the backend would return if ever proxied.
  elseif
    (
      path == "/orgs/testorg/interaction-limits"
      or path == "/repos/octocat/hello-world/interaction-limits"
      or path == "/user/interaction-limits"
    ) and (GetMethod() == "GET" or GetMethod() == "PUT" or GetMethod() == "DELETE")
  then
    SetStatus(404, "Not Found")

  -- Packages ------------------------------------------------------------------
  elseif path == "/api/v4/groups/testorg/packages" then
    local GL_PKG_LIST = '[{"id":1,"name":"web-app","version":"1.0.0","package_type":"npm",'
      .. '"created_at":"2024-01-01T00:00:00Z","project_id":1,'
      .. '"_links":{"web_path":"/testorg/proj/-/packages/1"}},'
      .. '{"id":2,"name":"web-app","version":"2.0.0","package_type":"npm",'
      .. '"created_at":"2024-02-01T00:00:00Z","project_id":1,'
      .. '"_links":{"web_path":"/testorg/proj/-/packages/2"}}]'
    SetStatus(200, "OK")
    json(GL_PKG_LIST)
  elseif path == "/api/v4/projects/1/packages/1" and GetMethod() == "DELETE" then
    SetStatus(204, "No Content")
  elseif path == "/api/v4/projects/1/packages/2" and GetMethod() == "DELETE" then
    SetStatus(204, "No Content")

  -- Markdown ------------------------------------------------------------------
  elseif path == "/api/v4/markdown" and GetMethod() == "POST" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('{"html":"<p>Hello <strong>world</strong></p>"}')

  -- Gitignore templates --------------------------------------------------------
  elseif path == "/api/v4/templates/gitignores" then
    SetStatus(200, "OK")
    json('[{"key":"C","name":"C"},{"key":"Go","name":"Go"}]')
  elseif path == "/api/v4/templates/gitignores/C" then
    SetStatus(200, "OK")
    json('{"name":"C","content":"# C gitignore\\n*.o\\n*.a\\n"}')
  elseif path == "/api/v4/templates/gitignores/Nonexistent" then
    SetStatus(404, "Not Found")
    json('{"message":"404 Not Found"}')

  -- License templates ----------------------------------------------------------
  elseif path == "/api/v4/templates/licenses" then
    SetStatus(200, "OK")
    json('[{"key":"mit","name":"MIT License"},{"key":"apache-2.0","name":"Apache License 2.0"}]')
  elseif path == "/api/v4/templates/licenses/mit" then
    SetStatus(200, "OK")
    json(
      '{"key":"mit","name":"MIT License",'
        .. '"html_url":"http://choosealicense.com/licenses/mit/",'
        .. '"description":"A permissive license.",'
        .. '"content":"MIT License\\n\\nCopyright (c) [year] [fullname]",'
        .. '"permissions":["commercial-use","modifications","distribution","private-use"],'
        .. '"conditions":["include-copyright"],'
        .. '"limitations":["liability","warranty"]}'
    )
  elseif path == "/api/v4/templates/licenses/Nonexistent" then
    SetStatus(404, "Not Found")
    json('{"message":"404 Not Found"}')

  -- Repo license file ----------------------------------------------------------
  elseif path == pb .. "/repository/files/LICENSE" then
    SetStatus(200, "OK")
    json(
      '{"file_name":"LICENSE","file_path":"LICENSE","blob_id":"abc123",'
        .. '"size":100,"encoding":"base64","content":"SGVsbG8gV29ybGQ="}'
    )

  -- Migrations: GitLab has per-project export, not GitHub-style org/user migrations.
  -- confusio returns fixed responses without proxying, but routes are documented here.
  -- POST /projects/:id/export → 202 Accepted (starts export asynchronously)
  elseif path == pb .. "/export" and GetMethod() == "POST" then
    SetStatus(202, "Accepted")
  -- GET /projects/:id/export → export status
  elseif path == pb .. "/export" then
    SetStatus(200, "OK")
    json('{"export_status":"finished"}')
  -- GET /projects/:id/export/download → redirect to archive
  elseif path == pb .. "/export/download" then
    SetStatus(302, "Found")
    SetHeader("Location", "https://storage.example.com/octocat-hello-world-export.tar.gz")
  else
    SetStatus(404, "Not Found")
  end
end
