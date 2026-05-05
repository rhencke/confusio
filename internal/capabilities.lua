-- Capability module helpers.
--
-- Provides shared primitives for building provider capability modules.
-- Capability modules are tables of named domain operations (e.g. get, list,
-- create, update, delete) that own fetch + error mapping + translation for one
-- resource type.  Both REST handlers and GraphQL resolvers call into these to
-- avoid duplicating fetch logic across the two API surfaces.
--
-- Capability operations return (data, nil) on success or (nil, err) on failure.
-- err is a table { status = N, message = string }, where:
--   status 0   — network / connection failure; map to HTTP 503
--   status N   — upstream HTTP status code (e.g. 404, 403, 429, 500)
--
-- REST handlers call a capability operation to get data, then pass the result to
-- the cap_rest_* adapter that writes the HTTP response.  GraphQL resolvers call
-- a capability operation and check `if not data then return nil end`.
--
-- cap_fetch_paged returns a three-value tuple (data, headers, nil) on success
-- and (nil, nil, err) on failure, matching the REST paged-list adapter.
--
-- Globals exported:
--   cap_err          — build { status, message } error table
--   cap_fetch        — GET/mutate one item; decode JSON; return (data, nil)|(nil, err)
--   cap_fetch_paged  — like cap_fetch but also returns response headers for pagination
--   cap_rest_respond — REST adapter: respond 200+data or error status
--   cap_rest_created — REST adapter: respond 201+data or error status
--   cap_rest_204     — REST adapter: respond 204 No Content or error status
--   cap_rest_paged   — REST adapter: respond 200+Link-rewrite or error status

-- cap_err builds a structured capability error value.
-- status: HTTP status code, or 0 for a network/connection failure
-- message: human-readable description (used for logging and GraphQL errors)
function cap_err(status, message) -- luacheck: globals cap_err
  return { status = status, message = message }
end

-- cap_fetch calls fetch_json, checks the response status, and decodes the JSON body.
--
-- fetch_json: the backend's local fetch function from its transport stack
-- url:        full upstream URL
-- method:     HTTP method string, or nil for GET
-- body:       request body (JSON-encoded string), or nil
--
-- Returns (decoded_table, nil)      on 2xx with valid JSON.
-- Returns (nil, err)               on network failure, non-2xx, or bad JSON.
function cap_fetch(fetch_json, url, method, body) -- luacheck: globals cap_fetch
  local ok, status, _, raw = fetch_json(url, method, body)
  if not ok then
    return nil, cap_err(0, "network error fetching " .. url)
  end
  if status < 200 or status >= 300 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " fetching " .. url)
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, cap_err(status, "invalid JSON from " .. url)
  end
  return decoded, nil
end

-- cap_fetch_paged is like cap_fetch but also returns response headers.
-- Capability operations that need to forward pagination metadata (Link header,
-- X-Total, X-Total-Count) use this variant.
--
-- Returns (decoded_table, headers_table, nil)    on success.
-- Returns (nil,           nil,           err)    on failure.
-- headers_table is {} when the upstream returns no headers.
function cap_fetch_paged(fetch_json, url, method, body) -- luacheck: globals cap_fetch_paged
  local ok, status, headers, raw = fetch_json(url, method, body)
  if not ok then
    return nil, nil, cap_err(0, "network error fetching " .. url)
  end
  if status < 200 or status >= 300 then
    return nil, nil, cap_err(status, "upstream error " .. tostring(status) .. " fetching " .. url)
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, nil, cap_err(status, "invalid JSON from " .. url)
  end
  return decoded, headers or {}, nil
end

-- cap_rest_respond is the REST surface adapter for single-item capability results.
-- Writes the HTTP response: 200 + (optionally translated) data on success, or the
-- upstream error status on failure.  Network errors map to 503.
--
-- data:      decoded result from a capability operation, or nil on failure
-- err:       error table from cap_err, or nil on success
-- translate: optional function applied to data before JSON serialization
function cap_rest_respond(data, err, translate) -- luacheck: globals cap_rest_respond
  if data then
    respond_json(200, translate and translate(data) or data)
  elseif err.status == 0 then
    respond_json(503, {})
  else
    respond_json(err.status, {})
  end
end

-- cap_rest_created is the REST adapter for create endpoints.
-- Like cap_rest_respond but responds 201 Created on success.
function cap_rest_created(data, err, translate) -- luacheck: globals cap_rest_created
  if data then
    respond_json(201, translate and translate(data) or data)
  elseif err.status == 0 then
    respond_json(503, {})
  else
    respond_json(err.status, {})
  end
end

-- cap_rest_204 is the REST adapter for DELETE / no-body mutation endpoints.
-- ok:  truthy on success (e.g. true returned by a successful delete operation)
-- err: error table from cap_err on failure
function cap_rest_204(ok, err) -- luacheck: globals cap_rest_204
  if ok then
    SetStatus(204, "No Content")
  elseif err.status == 0 then
    respond_json(503, {})
  else
    respond_json(err.status, {})
  end
end

-- cap_rest_paged is the REST adapter for paginated list endpoints.
-- Rewrites the upstream Link pagination header to point at confusio.
--
-- data, headers, err: the three-value tuple from cap_fetch_paged
-- page_params:        pagination mapping table (e.g. { per_page = "limit", page = "page" })
-- translate:          optional function applied to data before JSON serialization
function cap_rest_paged(data, headers, err, page_params, translate) -- luacheck: globals cap_rest_paged
  if data then
    local link = headers and (headers["Link"] or headers["link"])
    local rewritten = rewrite_link_header(link, page_params)
    -- set_preamble calls SetStatus which clears previously-set headers, so the
    -- Link header must be set AFTER set_preamble (same constraint as proxy_json_paged).
    set_preamble(200)
    if rewritten then
      SetHeader("Link", rewritten)
    end
    Write(EncodeJson(translate and translate(data) or data))
  elseif err.status == 0 then
    respond_json(503, {})
  else
    respond_json(err.status, {})
  end
end
