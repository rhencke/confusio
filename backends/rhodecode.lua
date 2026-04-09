-- RhodeCode backend handler overrides.
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer"))
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  -- Issues -----------------------------------------------------------------------
  -- RhodeCode has no native issue tracker; it integrates with external trackers
  -- such as JIRA. All issues, labels, milestones, and assignees endpoints fall
  -- back to the default empty-list / 404 handlers defined in .init.lua.

  -- Checks — RhodeCode has no native CI build system; all check endpoints are stubs.

  -- POST /repos/{owner}/{repo}/check-runs
  post_check_runs = function(_owner, _repo_name)
    local req = DecodeJson(GetBody() or "{}")
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      name = req.name or "",
      status = req.status or "queued",
      conclusion = req.conclusion,
      started_at = nil,
      completed_at = nil,
      output = {
        title = (req.output and req.output.title) or "",
        summary = (req.output and req.output.summary) or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = "",
      details_url = req.details_url or "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}
  get_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}
  patch_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations
  get_check_run_annotations = function(_owner, _repo_name, _check_run_id)
    set_preamble()
    Write("[]")
  end,

  -- POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest
  post_check_run_rerequest = function(_owner, _repo_name, _check_run_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs — no CI system; always empty
  get_commit_check_runs = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- Check Suites — no RhodeCode equivalent; all are stubs -------------------------

  -- POST /repos/{owner}/{repo}/check-suites
  post_check_suites = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-suites/preferences
  patch_check_suites_preferences = function(_owner, _repo_name) -- luacheck: ignore 212
    local req = DecodeJson(GetBody() or "{}") or {}
    respond_json(200, {
      preferences = req.auto_trigger_checks or {},
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}
  get_check_suite = function(owner, repo_name, check_suite_id)
    respond_json(200, {
      id = tonumber(check_suite_id) or 0,
      node_id = "",
      head_sha = "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs
  get_check_suite_check_runs = function(_owner, _repo_name, _check_suite_id)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest
  post_check_suite_rerequest = function(_owner, _repo_name, _check_suite_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-suites
  get_commit_check_suites = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_suites = {} })
  end,
  -- Migrations (https://docs.github.com/en/rest/migrations) ------------------
  -- RhodeCode has no org/user migration export API matching GitHub's stateful
  -- multi-repo model. All endpoints return fixed responses listed explicitly here.

  get_org_migrations = function()
    set_preamble()
    Write("[]")
  end,
  post_org_migrations = function()
    respond_json(501, { message = "Migrations are not supported by this backend." })
  end,
  get_org_migration = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_org_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_org_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_org_migration_repo_lock = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_org_migration_repos = function()
    set_preamble()
    Write("[]")
  end,
  get_user_migrations = function()
    set_preamble()
    Write("[]")
  end,
  post_user_migrations = function()
    respond_json(501, { message = "Migrations are not supported by this backend." })
  end,
  get_user_migration = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_user_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_user_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_user_migration_repo_lock = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_user_migration_repos = function()
    set_preamble()
    Write("[]")
  end,
}
