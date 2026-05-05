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
