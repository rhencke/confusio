-- GraphQL translators, connection helpers, and fetch utilities.
-- Provides shared functions used by backend resolvers to convert
-- GitHub REST-shaped responses into GraphQL-shaped responses.
--
-- Requires: EncodeBase64, DecodeBase64, DecodeJson (Redbean built-ins)
--
-- Globals exported:
--   encode_node_id(type_name, local_id)
--   decode_node_id(encoded)
--   graphql_fetch(fetch_json, path[, method[, body]])
--   graphql_fetch_with_headers(fetch_json, path[, method[, body]])

-- ---------------------------------------------------------------------------
-- Node ID encoding
-- ---------------------------------------------------------------------------

-- encode_node_id is global: base64-encodes a GraphQL node ID as "TypeName:local_id".
-- local_id is the REST path segment that identifies the object:
--   Repository  → "owner/repo"
--   User/Org    → "login"
--   Issue/PR    → "owner/repo/number"
--   Comment     → "owner/repo/comment_id"
function encode_node_id(type_name, local_id) -- luacheck: globals encode_node_id
  return EncodeBase64(type_name .. ":" .. local_id)
end

-- decode_node_id is global: decodes a node ID produced by encode_node_id.
-- Returns (type_name, local_id) on success.
-- Returns (nil, nil) if the value is absent, not valid base64, or missing the colon separator.
function decode_node_id(encoded) -- luacheck: globals decode_node_id
  if not encoded then
    return nil, nil
  end
  local decoded = DecodeBase64(encoded)
  if not decoded then
    return nil, nil
  end
  local t, id = decoded:match("^([^:]+):(.+)$")
  return t, id -- both nil when the pattern does not match
end

-- ---------------------------------------------------------------------------
-- Fetch helpers
-- ---------------------------------------------------------------------------

-- graphql_fetch is global: thin adapter over a backend's fetch_json for use in resolvers.
-- Calls fetch_json, checks the status, decodes the JSON body, and returns a simple pair.
--
-- Returns (decoded_table, nil)       on HTTP 2xx with a valid JSON body.
-- Returns (nil, error_string)        on network failure, non-2xx status, or bad JSON.
--
-- fetch_json: the backend's local fetch function (from make_backend_transport)
-- path:       full URL to request
-- method:     HTTP method string, or nil for GET
-- body:       request body (JSON-encoded string) or nil
function graphql_fetch(fetch_json, path, method, body) -- luacheck: globals graphql_fetch
  local ok, status, _, raw = fetch_json(path, method, body)
  if not ok then
    return nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, "upstream error " .. tostring(status) .. " fetching " .. path
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, "invalid JSON from upstream for " .. path
  end
  return decoded, nil
end

-- graphql_fetch_with_headers is global: like graphql_fetch but also returns response headers.
-- Resolvers that need X-Total or X-Total-Count for pagination use this variant.
--
-- Returns (decoded_table, headers_table, nil)        on success (headers is {} when upstream omits them).
-- Returns (nil,           nil,           error_string) on failure.
function graphql_fetch_with_headers(fetch_json, path, method, body) -- luacheck: globals graphql_fetch_with_headers
  local ok, status, headers, raw = fetch_json(path, method, body)
  if not ok then
    return nil, nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, nil, "upstream error " .. tostring(status) .. " fetching " .. path
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, nil, "invalid JSON from upstream for " .. path
  end
  return decoded, headers or {}, nil
end
