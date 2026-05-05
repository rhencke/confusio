-- Shared backend registration helpers.

function register_graphql_local_id_node_resolver(b, key, fetch, translate) -- luacheck: globals register_graphql_local_id_node_resolver
  b:graphql(key, function(local_id, _ctx)
    local data, _ = fetch(local_id)
    if not data then
      return nil
    end
    return translate(data)
  end)
end

function register_graphql_login_query_resolver(b, key, missing_message, fetch, translate) -- luacheck: globals register_graphql_login_query_resolver
  b:graphql(key, function(_parent, args, ctx)
    if not args.login then
      graphql_error(ctx, missing_message)
      return nil
    end
    local data, _ = fetch(args.login)
    if not data then
      return nil
    end
    return translate(data)
  end)
end

function register_graphql_owner_repo_number_node_resolver(b, key, fetch, translate) -- luacheck: globals register_graphql_owner_repo_number_node_resolver
  b:graphql(key, function(local_id, _ctx)
    local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
    if not owner then
      return nil
    end
    local data, _ = fetch(owner, repo, number)
    if not data then
      return nil
    end
    return translate(data, owner, repo)
  end)
end

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
