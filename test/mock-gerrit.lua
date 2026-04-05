-- Mock Gerrit server.
-- Responds to Gerrit REST API paths used by backends/gerrit.lua.
-- All responses are plain JSON (no XSSI ")]}'\n" prefix) because:
--   - proxy_handler endpoints use DecodeJson directly
--   - gerrit_decode falls through to DecodeJson for non-prefixed bodies
-- config.base_url = http://localhost:{port}
-- Gerrit project names use "/" as separator, URL-encoded as "%2F" in paths.
-- Path normalization decodes %2F so matching uses readable paths.
function OnHttpRequest()
  local raw_path = GetPath()
  -- Decode percent-encoded slashes so we can match on readable paths
  -- regardless of whether Redbean decodes them or not.
  local path = raw_path:gsub("%%2[Ff]", "/")
  local method = GetMethod()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local ACCOUNT =
    '{"_account_id":1,"username":"octocat","name":"The Octocat","email":"octocat@github.com"}'

  local PROJECT = '{"id":"octocat%2Fhello-world","name":"octocat/hello-world",'
    .. '"description":"My first repo","state":"ACTIVE"}'

  local BRANCH_MAIN = '{"ref":"refs/heads/main","revision":"abc123def456"}'
  local BRANCH_DEVEL = '{"ref":"refs/heads/develop","revision":"def456abc123"}'
  -- refs/meta/config is intentionally included to verify the branches
  -- filter in get_repo_branches (only refs/heads/* should appear in output).
  local BRANCH_META = '{"ref":"refs/meta/config","revision":"meta123456789"}'

  local rp = "/a/projects/octocat/hello-world"

  -- Health check ---------------------------------------------------------------
  if path == "/a/config/server/version" then
    SetStatus(200, "OK")
    json('{"version":"3.10.0"}')

  -- Repo list: get_user_repos / get_repositories (no ?p=) --------------------
  -- get_users_repos (?p=octocat/) returns the same set filtered by prefix.
  elseif path == "/a/projects/" and method == "GET" then
    SetStatus(200, "OK")
    json(
      '{"octocat/hello-world":{"id":"octocat%2Fhello-world",'
        .. '"description":"My first repo","state":"ACTIVE"}}'
    )

  -- Single repo ---------------------------------------------------------------
  elseif path == rp and method == "GET" then
    SetStatus(200, "OK")
    json(PROJECT)

  -- Patch repo config ---------------------------------------------------------
  elseif path == rp .. "/config" and method == "PUT" then
    SetStatus(200, "OK")
    json(PROJECT)

  -- Branch list ---------------------------------------------------------------
  elseif path == rp .. "/branches/" then
    SetStatus(200, "OK")
    json("[" .. BRANCH_MAIN .. "," .. BRANCH_DEVEL .. "," .. BRANCH_META .. "]")

  -- Single branch -------------------------------------------------------------
  elseif path == rp .. "/branches/refs/heads/main" then
    SetStatus(200, "OK")
    json(BRANCH_MAIN)

  -- Tag list ------------------------------------------------------------------
  elseif path == rp .. "/tags/" then
    SetStatus(200, "OK")
    json('[{"ref":"refs/tags/v1.0","revision":"abc123def456"}]')

  -- Single commit -------------------------------------------------------------
  elseif path == rp .. "/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '{"commit":"abc123def456","message":"Initial commit",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com","date":"2011-01-26T19:01:12Z"},'
        .. '"committer":{"name":"Octocat","email":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}'
    )

  -- File contents: /branches/{ref}/files/{path}/content ---------------------
  elseif
    path:find("^/a/projects/octocat/hello%-world/branches/")
    and path:find("/files/")
    and path:find("/content$")
  then
    SetStatus(200, "OK")
    -- Raw base64-encoded content (as Gerrit returns it)
    Write("SGVsbG8gV29ybGQ=")

  -- Authenticated user --------------------------------------------------------
  elseif path == "/a/accounts/self" then
    SetStatus(200, "OK")
    json(ACCOUNT)

  -- User by username ----------------------------------------------------------
  elseif path == "/a/accounts/octocat" then
    SetStatus(200, "OK")
    json(ACCOUNT)

  -- User list -----------------------------------------------------------------
  elseif path == "/a/accounts/" then
    SetStatus(200, "OK")
    json("[" .. ACCOUNT .. "]")
  else
    SetStatus(404, "Not Found")
  end
end
