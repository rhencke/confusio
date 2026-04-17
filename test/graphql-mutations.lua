-- Unit tests for GraphQL mutation execution.
-- Covers: subscription rejection, mutation __typename, get_client_mutation_id,
-- mutation resolver dispatch, clientMutationId round-trip, and serial execution.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.
-- ============================================================

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL reset_response _last_status _last_body _req_body

-- ============================================================
-- Test helpers (mirror of graphql-executor.lua helpers)
-- ============================================================

local function with_resolvers(tbl, fn)
  local saved = graphql_resolvers
  graphql_resolvers = tbl
  fn()
  graphql_resolvers = saved
end

local function call_handler(body_table)
  reset_response()
  _req_body = EncodeJson(body_table)
  graphql_handler()
  return DecodeJson(_last_body)
end

-- ============================================================
-- Subscription rejection
-- ============================================================

do -- subscription operation → BAD_USER_INPUT error
  local r = call_handler({ query = "subscription { __typename }" })
  ok(r.data == nil, "mutation: subscription rejected → data null")
  ok(
    r.errors and r.errors[1].message:find("subscription"),
    "mutation: subscription rejected → error mentions subscription"
  )
  ok(
    r.errors[1].extensions and r.errors[1].extensions.code == "BAD_USER_INPUT",
    "mutation: subscription rejected → BAD_USER_INPUT code"
  )
end

-- ============================================================
-- Mutation __typename
-- ============================================================

do -- mutation { __typename } → returns "Mutation"
  with_resolvers({}, function()
    local r = call_handler({ query = "mutation { __typename }" })
    ok(r.errors == nil or #r.errors == 0, "mutation: __typename → no errors")
    eq(r.data.__typename, "Mutation", "mutation: __typename returns root type name")
  end)
end

-- ============================================================
-- get_client_mutation_id helper
-- ============================================================

do -- present clientMutationId → returns the string
  local cmid = get_client_mutation_id({ input = { clientMutationId = "abc-123" } })
  eq(cmid, "abc-123", "get_client_mutation_id: present → returns value")
end

do -- absent clientMutationId (input has other fields) → nil
  local cmid = get_client_mutation_id({ input = { name = "myrepo" } })
  ok(cmid == nil, "get_client_mutation_id: absent → nil")
end

do -- empty input → nil
  local cmid = get_client_mutation_id({ input = {} })
  ok(cmid == nil, "get_client_mutation_id: empty input → nil")
end

do -- nil args → nil (no crash)
  local cmid = get_client_mutation_id(nil)
  ok(cmid == nil, "get_client_mutation_id: nil args → nil")
end

do -- nil input field → nil (no crash)
  local cmid = get_client_mutation_id({})
  ok(cmid == nil, "get_client_mutation_id: no input field → nil")
end

-- ============================================================
-- Mutation resolver dispatch
-- ============================================================

do -- mutation resolver is called and result is returned
  with_resolvers({
    ["Mutation.createRepository"] = function(_parent, _args, _ctx)
      return {
        repository = { nameWithOwner = "fido/bones", __typename = "Repository" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createRepository(input: { name: "bones", visibility: PUBLIC }) {
            repository { nameWithOwner }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "mutation: resolver dispatched → no errors")
    ok(r.data.createRepository ~= nil, "mutation: resolver dispatched → payload present")
    eq(
      r.data.createRepository.repository.nameWithOwner,
      "fido/bones",
      "mutation: resolver dispatched → field value returned"
    )
  end)
end

do -- mutation resolver absent → null payload (no crash)
  with_resolvers({}, function()
    local r = call_handler({
      query = [[
        mutation {
          createRepository(input: { name: "bones", visibility: PUBLIC }) {
            clientMutationId
          }
        }
      ]],
    })
    -- No resolver registered → payload is null, but no hard error
    ok(r.data ~= nil, "mutation: no resolver → data not null at root")
    ok(r.data.createRepository == nil, "mutation: no resolver → payload is null")
  end)
end

-- ============================================================
-- clientMutationId round-trip
-- ============================================================

do -- clientMutationId is echoed back in payload
  with_resolvers({
    ["Mutation.createRepository"] = function(_parent, args, _ctx)
      local cmid = get_client_mutation_id(args)
      return {
        repository = { nameWithOwner = "fido/walkies", __typename = "Repository" },
        clientMutationId = cmid,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createRepository(input: {
            name: "walkies",
            visibility: PUBLIC,
            clientMutationId: "relay-42"
          }) {
            repository { nameWithOwner }
            clientMutationId
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "mutation: clientMutationId round-trip → no errors")
    eq(
      r.data.createRepository.clientMutationId,
      "relay-42",
      "mutation: clientMutationId round-trip → value echoed back"
    )
  end)
end

-- ============================================================
-- Serial execution: two mutations in one document
-- ============================================================

do -- two mutations execute in order; both results present
  local call_order = {}
  with_resolvers({
    ["Mutation.addStar"] = function(_parent, _args, _ctx)
      call_order[#call_order + 1] = "addStar"
      return {
        starrable = {
          id = "UmVwb3NpdG9yeToxMjM=",
          viewerHasStarred = true,
          __typename = "Repository",
        },
        clientMutationId = nil,
      }
    end,
    ["Mutation.createRepository"] = function(_parent, _args, _ctx)
      call_order[#call_order + 1] = "createRepository"
      return {
        repository = { nameWithOwner = "fido/new-repo", __typename = "Repository" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          addStar(input: { starrableId: "UmVwb3NpdG9yeToxMjM=" }) {
            starrable { id viewerHasStarred }
          }
          createRepository(input: { name: "new-repo", visibility: PUBLIC }) {
            repository { nameWithOwner }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "mutation: serial execution → no errors")
    ok(r.data ~= nil, "mutation: serial execution → data present")
    ok(r.data.addStar ~= nil, "mutation: serial execution → first result present")
    ok(r.data.createRepository ~= nil, "mutation: serial execution → second result present")
    eq(#call_order, 2, "mutation: serial execution → both resolvers called")
    eq(call_order[1], "addStar", "mutation: serial execution → first resolver first")
    eq(call_order[2], "createRepository", "mutation: serial execution → second resolver second")
  end)
end

do -- mutation validation error: unknown field on Mutation type
  local r = call_handler({ query = "mutation { nonexistentMutationField123 }" })
  ok(r.data == nil, "mutation: validation error → data null")
  ok(
    r.errors and r.errors[1].message:find("nonexistentMutationField123"),
    "mutation: validation error mentions field name"
  )
  ok(
    r.errors[1].extensions and r.errors[1].extensions.code == "VALIDATION_ERROR",
    "mutation: validation error → VALIDATION_ERROR code"
  )
end

-- ============================================================
-- Issue mutation dispatch
-- ============================================================

-- Node IDs used in tests:
--   Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
--   Issue:octocat/hello-world/1    = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x

do -- createIssue resolver is dispatched and returns issue payload
  with_resolvers({
    ["Mutation.createIssue"] = function(_parent, _args, _ctx)
      return {
        issue = { number = 1, title = "Found a bug", state = "OPEN", __typename = "Issue" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createIssue(input: {
            repositoryId: "UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk",
            title: "Found a bug"
          }) {
            issue { number title state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "createIssue: resolver dispatched → no errors")
    ok(r.data.createIssue ~= nil, "createIssue: resolver dispatched → payload present")
    eq(
      r.data.createIssue.issue.title,
      "Found a bug",
      "createIssue: resolver dispatched → title returned"
    )
    eq(
      r.data.createIssue.issue.state,
      "OPEN",
      "createIssue: resolver dispatched → state returned"
    )
  end)
end

do -- createIssue clientMutationId round-trip
  with_resolvers({
    ["Mutation.createIssue"] = function(_parent, args, _ctx)
      return {
        issue = { number = 1, title = "Found a bug", state = "OPEN", __typename = "Issue" },
        clientMutationId = get_client_mutation_id(args),
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createIssue(input: {
            repositoryId: "UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk",
            title: "Found a bug",
            clientMutationId: "issue-relay-1"
          }) {
            issue { number }
            clientMutationId
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "createIssue: clientMutationId round-trip → no errors")
    eq(
      r.data.createIssue.clientMutationId,
      "issue-relay-1",
      "createIssue: clientMutationId round-trip → value echoed back"
    )
  end)
end

do -- updateIssue resolver is dispatched and returns issue payload
  with_resolvers({
    ["Mutation.updateIssue"] = function(_parent, _args, _ctx)
      return {
        issue = { number = 1, title = "Found a bug", state = "OPEN", __typename = "Issue" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          updateIssue(input: {
            id: "SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x",
            title: "Updated bug"
          }) {
            issue { number title state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "updateIssue: resolver dispatched → no errors")
    ok(r.data.updateIssue ~= nil, "updateIssue: resolver dispatched → payload present")
    eq(r.data.updateIssue.issue.number, 1, "updateIssue: resolver dispatched → number returned")
  end)
end

do -- closeIssue and reopenIssue resolvers are dispatched
  with_resolvers({
    ["Mutation.closeIssue"] = function(_parent, _args, _ctx)
      return {
        issue = { number = 1, title = "Found a bug", state = "CLOSED", __typename = "Issue" },
        clientMutationId = nil,
      }
    end,
    ["Mutation.reopenIssue"] = function(_parent, _args, _ctx)
      return {
        issue = { number = 1, title = "Found a bug", state = "OPEN", __typename = "Issue" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          closeIssue(input: { issueId: "SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x" }) {
            issue { number state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "closeIssue: resolver dispatched → no errors")
    eq(r.data.closeIssue.issue.state, "CLOSED", "closeIssue: resolver dispatched → state CLOSED")

    r = call_handler({
      query = [[
        mutation {
          reopenIssue(input: { issueId: "SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x" }) {
            issue { number state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "reopenIssue: resolver dispatched → no errors")
    eq(r.data.reopenIssue.issue.state, "OPEN", "reopenIssue: resolver dispatched → state OPEN")
  end)
end

-- ============================================================
-- Pull request mutation dispatch
-- ============================================================

-- Node IDs used in tests:
--   Repository:octocat/hello-world      = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
--   PullRequest:octocat/hello-world/1   = UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x

do -- createPullRequest resolver is dispatched and returns pullRequest payload
  with_resolvers({
    ["Mutation.createPullRequest"] = function(_parent, _args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "OPEN",
          __typename = "PullRequest",
        },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createPullRequest(input: {
            repositoryId: "UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk",
            title: "A great PR",
            headRefName: "feature",
            baseRefName: "main"
          }) {
            pullRequest { number title state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "createPullRequest: resolver dispatched → no errors")
    ok(
      r.data.createPullRequest ~= nil,
      "createPullRequest: resolver dispatched → payload present"
    )
    eq(
      r.data.createPullRequest.pullRequest.title,
      "A great PR",
      "createPullRequest: resolver dispatched → title returned"
    )
    eq(
      r.data.createPullRequest.pullRequest.state,
      "OPEN",
      "createPullRequest: resolver dispatched → state returned"
    )
  end)
end

do -- createPullRequest clientMutationId round-trip
  with_resolvers({
    ["Mutation.createPullRequest"] = function(_parent, args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "OPEN",
          __typename = "PullRequest",
        },
        clientMutationId = get_client_mutation_id(args),
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          createPullRequest(input: {
            repositoryId: "UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk",
            title: "A great PR",
            headRefName: "feature",
            baseRefName: "main",
            clientMutationId: "pr-relay-1"
          }) {
            pullRequest { number }
            clientMutationId
          }
        }
      ]],
    })
    ok(
      r.errors == nil or #r.errors == 0,
      "createPullRequest: clientMutationId round-trip → no errors"
    )
    eq(
      r.data.createPullRequest.clientMutationId,
      "pr-relay-1",
      "createPullRequest: clientMutationId round-trip → value echoed back"
    )
  end)
end

do -- updatePullRequest resolver is dispatched and returns pullRequest payload
  with_resolvers({
    ["Mutation.updatePullRequest"] = function(_parent, _args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "OPEN",
          __typename = "PullRequest",
        },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          updatePullRequest(input: {
            pullRequestId: "UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x",
            title: "Updated PR"
          }) {
            pullRequest { number title state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "updatePullRequest: resolver dispatched → no errors")
    ok(
      r.data.updatePullRequest ~= nil,
      "updatePullRequest: resolver dispatched → payload present"
    )
    eq(
      r.data.updatePullRequest.pullRequest.number,
      1,
      "updatePullRequest: resolver dispatched → number returned"
    )
  end)
end

do -- closePullRequest, reopenPullRequest, and mergePullRequest resolvers are dispatched
  with_resolvers({
    ["Mutation.closePullRequest"] = function(_parent, _args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "CLOSED",
          __typename = "PullRequest",
        },
        clientMutationId = nil,
      }
    end,
    ["Mutation.reopenPullRequest"] = function(_parent, _args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "OPEN",
          __typename = "PullRequest",
        },
        clientMutationId = nil,
      }
    end,
    ["Mutation.mergePullRequest"] = function(_parent, _args, _ctx)
      return {
        pullRequest = {
          number = 1,
          title = "A great PR",
          state = "MERGED",
          merged = true,
          __typename = "PullRequest",
        },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          closePullRequest(input: {
            pullRequestId: "UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x"
          }) {
            pullRequest { number state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "closePullRequest: resolver dispatched → no errors")
    eq(
      r.data.closePullRequest.pullRequest.state,
      "CLOSED",
      "closePullRequest: resolver dispatched → state CLOSED"
    )

    r = call_handler({
      query = [[
        mutation {
          reopenPullRequest(input: {
            pullRequestId: "UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x"
          }) {
            pullRequest { number state }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "reopenPullRequest: resolver dispatched → no errors")
    eq(
      r.data.reopenPullRequest.pullRequest.state,
      "OPEN",
      "reopenPullRequest: resolver dispatched → state OPEN"
    )

    r = call_handler({
      query = [[
        mutation {
          mergePullRequest(input: {
            pullRequestId: "UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x"
          }) {
            pullRequest { number state merged }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "mergePullRequest: resolver dispatched → no errors")
    eq(
      r.data.mergePullRequest.pullRequest.state,
      "MERGED",
      "mergePullRequest: resolver dispatched → state MERGED"
    )
  end)
end

-- ============================================================
-- Comment mutation dispatch
-- ============================================================

-- Node IDs used in tests:
--   Issue:octocat/hello-world/1         = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
--   PullRequest:octocat/hello-world/1   = UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x
--   IssueComment:octocat/hello-world/1  = SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==

do -- addComment resolver is dispatched with Issue subjectId and returns commentEdge
  with_resolvers({
    ["Mutation.addComment"] = function(_parent, _args, _ctx)
      return {
        commentEdge = {
          __typename = "IssueCommentEdge",
          cursor = "cGFnZTox",
          node = { body = "This is a comment", __typename = "IssueComment" },
        },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          addComment(input: {
            subjectId: "SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x",
            body: "This is a comment"
          }) {
            commentEdge { node { body } }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "addComment: resolver dispatched → no errors")
    ok(r.data.addComment ~= nil, "addComment: resolver dispatched → payload present")
    eq(
      r.data.addComment.commentEdge.node.body,
      "This is a comment",
      "addComment: resolver dispatched → body returned"
    )
  end)
end

do -- addComment clientMutationId round-trip
  with_resolvers({
    ["Mutation.addComment"] = function(_parent, args, _ctx)
      return {
        commentEdge = {
          __typename = "IssueCommentEdge",
          cursor = "cGFnZTox",
          node = { body = "This is a comment", __typename = "IssueComment" },
        },
        clientMutationId = get_client_mutation_id(args),
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          addComment(input: {
            subjectId: "SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x",
            body: "This is a comment",
            clientMutationId: "comment-relay-1"
          }) {
            commentEdge { node { body } }
            clientMutationId
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "addComment: clientMutationId round-trip → no errors")
    eq(
      r.data.addComment.clientMutationId,
      "comment-relay-1",
      "addComment: clientMutationId round-trip → value echoed back"
    )
  end)
end

do -- updateIssueComment resolver is dispatched and returns issueComment payload
  with_resolvers({
    ["Mutation.updateIssueComment"] = function(_parent, _args, _ctx)
      return {
        issueComment = { body = "Updated comment", __typename = "IssueComment" },
        clientMutationId = nil,
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          updateIssueComment(input: {
            id: "SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==",
            body: "Updated comment"
          }) {
            issueComment { body }
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "updateIssueComment: resolver dispatched → no errors")
    ok(
      r.data.updateIssueComment ~= nil,
      "updateIssueComment: resolver dispatched → payload present"
    )
    eq(
      r.data.updateIssueComment.issueComment.body,
      "Updated comment",
      "updateIssueComment: resolver dispatched → body returned"
    )
  end)
end

do -- updateIssueComment clientMutationId round-trip
  with_resolvers({
    ["Mutation.updateIssueComment"] = function(_parent, args, _ctx)
      return {
        issueComment = { body = "Updated comment", __typename = "IssueComment" },
        clientMutationId = get_client_mutation_id(args),
      }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          updateIssueComment(input: {
            id: "SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==",
            body: "Updated comment",
            clientMutationId: "comment-relay-2"
          }) {
            issueComment { body }
            clientMutationId
          }
        }
      ]],
    })
    ok(
      r.errors == nil or #r.errors == 0,
      "updateIssueComment: clientMutationId round-trip → no errors"
    )
    eq(
      r.data.updateIssueComment.clientMutationId,
      "comment-relay-2",
      "updateIssueComment: clientMutationId round-trip → value echoed back"
    )
  end)
end

do -- deleteIssueComment resolver is dispatched; payload contains only clientMutationId
  with_resolvers({
    ["Mutation.deleteIssueComment"] = function(_parent, _args, _ctx)
      return { clientMutationId = nil }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          deleteIssueComment(input: {
            id: "SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ=="
          }) {
            clientMutationId
          }
        }
      ]],
    })
    ok(r.errors == nil or #r.errors == 0, "deleteIssueComment: resolver dispatched → no errors")
    ok(
      r.data.deleteIssueComment ~= nil,
      "deleteIssueComment: resolver dispatched → payload present"
    )
  end)
end

do -- deleteIssueComment clientMutationId round-trip
  with_resolvers({
    ["Mutation.deleteIssueComment"] = function(_parent, args, _ctx)
      return { clientMutationId = get_client_mutation_id(args) }
    end,
  }, function()
    local r = call_handler({
      query = [[
        mutation {
          deleteIssueComment(input: {
            id: "SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==",
            clientMutationId: "comment-relay-3"
          }) {
            clientMutationId
          }
        }
      ]],
    })
    ok(
      r.errors == nil or #r.errors == 0,
      "deleteIssueComment: clientMutationId round-trip → no errors"
    )
    eq(
      r.data.deleteIssueComment.clientMutationId,
      "comment-relay-3",
      "deleteIssueComment: clientMutationId round-trip → value echoed back"
    )
  end)
end
