-- Mock Tuleap server. Uses Tuleap REST API v1 at /api/v1/.
-- Projects are identified by shortname; git repos live inside projects.
function OnHttpRequest()
  local path = GetPath()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local PROJECT = '{"id":101,"uri":"projects/101","label":"Hello World",'
    .. '"shortname":"octocat","status":"A","access":"public",'
    .. '"description":"My first project"}'

  local REPO = '{"id":1,"uri":"git/1","name":"hello-world",'
    .. '"description":"My first repo",'
    .. '"http_url":"https://tuleap.example.com/plugins/git/octocat/hello-world",'
    .. '"clone_http_url":"https://tuleap.example.com/plugins/git/octocat/hello-world.git",'
    .. '"clone_ssh_url":"ssh://tuleap.example.com/octocat/hello-world.git",'
    .. '"default_branch":"main",'
    .. '"project":{"id":101,"uri":"projects/101","label":"Hello World","shortname":"octocat"}}'

  local USER = '{"id":42,"uri":"users/42","user_url":"/users/octocat",'
    .. '"real_name":"The Octocat","display_name":"The Octocat (octocat)",'
    .. '"username":"octocat","ldap_id":"","avatar_url":"","is_anonymous":false,"has_avatar":false}'

  -- Health check / project search -----------------------------------------------
  if path == "/api/v1/projects" then
    SetStatus(200, "OK")
    json("[" .. PROJECT .. "]")

  -- Git repos in a project ------------------------------------------------------
  elseif path == "/api/v1/projects/101/git" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Single git repo by ID -------------------------------------------------------
  elseif path == "/api/v1/git/1" then
    SetStatus(200, "OK")
    json(REPO)

  -- User search / list ----------------------------------------------------------
  elseif path == "/api/v1/users" then
    SetStatus(200, "OK")
    json("[" .. USER .. "]")

  -- Single user by ID -----------------------------------------------------------
  elseif path == "/api/v1/users/42" then
    SetStatus(200, "OK")
    json(USER)
  else
    SetStatus(404, "Not Found")
  end
end
