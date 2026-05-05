-- Shared backend registration helpers.

function register_repo_rest_handlers(b, repos, topics, pages) -- luacheck: globals register_repo_rest_handlers
  b:rest("get_repo", function(owner, repo_name)
    local data, err = repos.get(owner, repo_name)
    cap_rest_respond(data, err)
  end)

  b:rest("patch_repo", function(owner, repo_name)
    local data, err = repos.update(owner, repo_name, GetBody())
    cap_rest_respond(data, err)
  end)

  b:rest("delete_repo", function(owner, repo_name)
    local ok, err = repos.delete(owner, repo_name)
    cap_rest_204(ok, err)
  end)

  b:rest("get_user_repos", function()
    local items, hdrs, err = repos.list_user()
    cap_rest_paged(items, hdrs, err, pages)
  end)

  b:rest("post_user_repos", function()
    local data, err = repos.create_user(GetBody())
    cap_rest_created(data, err)
  end)

  b:rest("get_org_repos", function(org)
    local items, hdrs, err = repos.list_org(org)
    cap_rest_paged(items, hdrs, err, pages)
  end)

  b:rest("post_org_repos", function(org)
    local data, err = repos.create_org(org, GetBody())
    cap_rest_created(data, err)
  end)

  b:rest("get_repo_topics", function(owner, repo_name)
    local data, err = topics.get_topics(owner, repo_name)
    cap_rest_respond(data, err)
  end)

  b:rest("put_repo_topics", function(owner, repo_name)
    local data, err = topics.put_topics(owner, repo_name, GetBody())
    cap_rest_respond(data, err)
  end)
end

local function repo_resource_id(opts, owner, repo_name, route_id)
  if not opts.resolve_id then
    return route_id
  end

  local id = opts.resolve_id(owner, repo_name, route_id)
  if not id then
    respond_json(404, { message = opts.not_found_message or "Not found" })
    return nil
  end
  return id
end

function register_repo_resource_rest_handlers(b, opts) -- luacheck: globals register_repo_resource_rest_handlers
  local cap = opts.cap
  local routes = opts.routes

  if routes.list then
    b:rest(routes.list, function(owner, repo_name)
      local items, hdrs, err = cap.list(owner, repo_name)
      cap_rest_paged(items, hdrs, err, opts.pages)
    end)
  end

  if routes.create then
    b:rest(routes.create, function(owner, repo_name)
      local data, err = cap.create(owner, repo_name, GetBody())
      cap_rest_created(data, err)
    end)
  end

  if routes.get then
    b:rest(routes.get, function(owner, repo_name, route_id)
      local id = repo_resource_id(opts, owner, repo_name, route_id)
      if not id then
        return
      end
      local data, err = cap.get(owner, repo_name, id)
      cap_rest_respond(data, err)
    end)
  end

  if routes.update then
    b:rest(routes.update, function(owner, repo_name, route_id)
      local id = repo_resource_id(opts, owner, repo_name, route_id)
      if not id then
        return
      end
      local data, err = cap.update(owner, repo_name, id, GetBody())
      cap_rest_respond(data, err)
    end)
  end

  if routes.delete then
    b:rest(routes.delete, function(owner, repo_name, route_id)
      local id = repo_resource_id(opts, owner, repo_name, route_id)
      if not id then
        return
      end
      local ok, err = cap.delete(owner, repo_name, id)
      cap_rest_204(ok, err)
    end)
  end
end
