-- Mock Launchpad server. Implements the Launchpad REST API (Malone) subset
-- needed by confusio: searchTasks, individual bugs, bug messages, and the
-- per-project task endpoint.
function OnHttpRequest()
  local path = GetPath()
  local op = GetParam("ws.op") or ""

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  -- Root health-check --------------------------------------------------------
  if path == "/devel/" then
    SetStatus(200, "OK")
    json('{"version":"devel"}')

  -- searchTasks on project ---------------------------------------------------
  -- GET /devel/~octocat/hello-world?ws.op=searchTasks
  elseif path == "/devel/~octocat/hello-world" and op == "searchTasks" then
    SetStatus(200, "OK")
    json(
      '{"total_size":1,"start":0,"entries":['
        .. '{"self_link":"https://api.launchpad.net/devel/~octocat/hello-world/+bug/1",'
        .. '"bug_link":"https://api.launchpad.net/devel/bugs/1",'
        .. '"title":"Found a bug",'
        .. '"status":"New",'
        .. '"importance":"Undecided",'
        .. '"owner_link":"https://api.launchpad.net/devel/~octocat",'
        .. '"assignee_link":null,'
        .. '"date_created":"2020-01-01T00:00:00.000000+00:00",'
        .. '"date_last_updated":"2020-01-02T00:00:00.000000+00:00",'
        .. '"date_closed":null}'
        .. "]}"
    )

  -- Single bug ---------------------------------------------------------------
  elseif path == "/devel/bugs/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,'
        .. '"self_link":"https://api.launchpad.net/devel/bugs/1",'
        .. '"title":"Found a bug",'
        .. '"description":"Bug description",'
        .. '"owner_link":"https://api.launchpad.net/devel/~octocat",'
        .. '"date_created":"2020-01-01T00:00:00.000000+00:00",'
        .. '"date_last_updated":"2020-01-02T00:00:00.000000+00:00"}'
    )
  elseif path == "/devel/bugs/9999" then
    SetStatus(404, "Not Found")
    json('{"status": 404, "message": "Not Found"}')

  -- Per-project task (for status lookup on single-issue fetch) ---------------
  elseif path == "/devel/~octocat/hello-world/+bug/1" then
    SetStatus(200, "OK")
    json(
      '{"self_link":"https://api.launchpad.net/devel/~octocat/hello-world/+bug/1",'
        .. '"bug_link":"https://api.launchpad.net/devel/bugs/1",'
        .. '"status":"New",'
        .. '"importance":"Undecided",'
        .. '"date_created":"2020-01-01T00:00:00.000000+00:00",'
        .. '"date_last_updated":"2020-01-02T00:00:00.000000+00:00"}'
    )

  -- Bug messages (comments) --------------------------------------------------
  elseif path == "/devel/bugs/1/messages" then
    SetStatus(200, "OK")
    json(
      '{"total_size":1,"start":1,"entries":['
        .. '{"index":1,'
        .. '"self_link":"https://api.launchpad.net/devel/bugs/1/messages/1",'
        .. '"subject":"Re: Found a bug",'
        .. '"content":"This is a comment",'
        .. '"owner_link":"https://api.launchpad.net/devel/~octocat",'
        .. '"date_created":"2020-01-03T00:00:00.000000+00:00"}'
        .. "]}"
    )
  else
    SetStatus(404, "Not Found")
  end
end
