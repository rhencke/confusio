-- Mock Phabricator Conduit API server.
-- Implements the subset needed by confusio: conduit.ping, project.search,
-- maniphest.search, and transaction.search.
function OnHttpRequest()
  local path = GetPath()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  -- Helper: wrap a result in Conduit envelope.
  local function conduit_ok(result_json)
    SetStatus(200, "OK")
    json('{"result":' .. result_json .. ',"error_code":null,"error_info":null}')
  end

  -- Health-check ---------------------------------------------------------------
  if path == "/api/conduit.ping" then
    conduit_ok('{"ip":"127.0.0.1","answer":"pong"}')

  -- project.search -------------------------------------------------------------
  -- Returns a project PHID for "hello-world" or "octocat/hello-world" slugs.
  elseif path == "/api/project.search" then
    local slug = GetParam("constraints[slugs][0]") or ""
    if slug == "hello-world" or slug == "octocat/hello-world" then
      conduit_ok(
        '{"data":[{'
          .. '"id":1,'
          .. '"type":"PROJ",'
          .. '"phid":"PHID-PROJ-testproject",'
          .. '"fields":{"name":"hello-world","slug":"hello-world"}'
          .. "}],"
          .. '"cursor":{"limit":1,"after":null,"before":null,"order":null}}'
      )
    else
      conduit_ok('{"data":[],"cursor":{"limit":1,"after":null,"before":null,"order":null}}')
    end

  -- maniphest.search -----------------------------------------------------------
  -- Supports: constraints[projects][0]=PHID-PROJ-testproject (list)
  --           constraints[ids][0]=1 (single task)
  --           constraints[ids][0]=9999 (not found)
  elseif path == "/api/maniphest.search" then
    local project_phid = GetParam("constraints[projects][0]") or ""
    local id_param = GetParam("constraints[ids][0]") or ""
    local task_json = "{"
      .. '"id":1,'
      .. '"type":"TASK",'
      .. '"phid":"PHID-TASK-001",'
      .. '"fields":{'
      .. '"name":"Found a bug",'
      .. '"authorPHID":"PHID-USER-octocat",'
      .. '"ownerPHID":null,'
      .. '"status":{"value":"open","name":"Open","color":null,"closed":false},'
      .. '"description":{"raw":"Bug description"},'
      .. '"dateCreated":1577836800,'
      .. '"dateModified":1577923200'
      .. "}}"
    if id_param == "9999" then
      conduit_ok('{"data":[],"cursor":{"limit":1,"after":null,"before":null,"order":null}}')
    elseif id_param == "1" or project_phid == "PHID-PROJ-testproject" then
      conduit_ok(
        '{"data":['
          .. task_json
          .. "],"
          .. '"cursor":{"limit":30,"after":null,"before":null,"order":null}}'
      )
    else
      conduit_ok('{"data":[],"cursor":{"limit":30,"after":null,"before":null,"order":null}}')
    end

  -- diffusion.commit.search ----------------------------------------------------
  -- Returns a commit PHID for SHA "abc123".
  elseif path == "/api/diffusion.commit.search" then
    local id_param = GetParam("constraints[identifiers][0]") or ""
    if id_param == "abc123" then
      conduit_ok(
        '{"data":[{'
          .. '"id":42,'
          .. '"type":"CMIT",'
          .. '"phid":"PHID-CMIT-abc123",'
          .. '"fields":{"identifier":"abc123","repositoryPHID":"PHID-REPO-testrepository"}'
          .. "}],"
          .. '"cursor":{"limit":1,"after":null,"before":null,"order":null}}'
      )
    else
      conduit_ok('{"data":[],"cursor":{"limit":1,"after":null,"before":null,"order":null}}')
    end

  -- harbormaster.build.search --------------------------------------------------
  -- Returns one build for commits linked to PHID-CMIT-abc123.
  elseif path == "/api/harbormaster.build.search" then
    local buildable_param = GetParam("constraints[buildables][0]") or ""
    if buildable_param == "PHID-CMIT-abc123" then
      conduit_ok(
        '{"data":[{'
          .. '"id":1,'
          .. '"type":"HMBD",'
          .. '"phid":"PHID-HMBD-testbuild",'
          .. '"fields":{'
          .. '"buildStatus":{"value":"passed","name":"Passed","color.ansi":"green"},'
          .. '"buildPlan":{"phid":"PHID-HMCP-testplan","name":"ci/test"},'
          .. '"buildable":{"phid":"PHID-HMBB-testbuildable","objectPHID":"PHID-CMIT-abc123"},'
          .. '"dateCreated":1577836800,'
          .. '"dateModified":1577923200'
          .. "}}],"
          .. '"cursor":{"limit":100,"after":null,"before":null,"order":null}}'
      )
    else
      conduit_ok('{"data":[],"cursor":{"limit":100,"after":null,"before":null,"order":null}}')
    end

  -- transaction.search ---------------------------------------------------------
  -- Returns one comment transaction for T1.
  elseif path == "/api/transaction.search" then
    local obj = GetParam("objectIdentifier") or ""
    if obj == "T1" then
      conduit_ok(
        '{"data":[{'
          .. '"id":10,'
          .. '"phid":"PHID-XACT-TASK-001",'
          .. '"type":"comment",'
          .. '"authorPHID":"PHID-USER-octocat",'
          .. '"dateCreated":1578009600,'
          .. '"dateModified":1578009600,'
          .. '"comments":[{"id":10,"phid":"PHID-XCMT-001","version":1,'
          .. '"authorPHID":"PHID-USER-octocat","dateCreated":1578009600,'
          .. '"content":{"raw":"This is a comment"},"removed":false}]'
          .. "}],"
          .. '"cursor":{"limit":30,"after":null,"before":null,"order":null}}'
      )
    else
      conduit_ok('{"data":[],"cursor":{"limit":30,"after":null,"before":null,"order":null}}')
    end

  -- Migrations ----------------------------------------------------------------
  -- Phabricator has no GitHub-style org/user migration API; confusio
  -- returns fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")
  else
    SetStatus(404, "Not Found")
  end
end
