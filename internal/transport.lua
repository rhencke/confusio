-- Transport helpers (global: backends/<name>.lua uses them).
--
-- append_page_params     — append translated pagination params to an upstream URL
-- make_fetch_opts        — build a Fetch options table forwarding the caller's auth header
-- make_proxy_handler     — factory: bind a fetch_json function to a proxy response helper
-- base_transport         — base Fetch/JSON transport layer
-- with_auth              — transport layer: add upstream Authorization
-- with_pagination        — transport layer: add paged proxy helpers
-- with_error_shape       — transport layer: map provider errors to GitHub-shaped errors
-- make_backend_transport — factory: build the full fetch+proxy scaffolding for a backend

-- append_page_params appends translated pagination params to url.
-- mapping: { per_page = "upstream_name", page = "upstream_name" }
--   Omit the page key for providers that only support limit (e.g. Sourcehut).
-- Reads per_page and page from the incoming GitHub-style request query string.
-- Returns url unchanged if neither applicable param is present in the request.
function append_page_params(url, mapping)
  local sep = url:find("?") and "&" or "?"
  local parts = {}
  local pp = GetParam("per_page")
  local pg = GetParam("page")
  if pp and pp ~= "" and mapping.per_page then
    parts[#parts + 1] = mapping.per_page .. "=" .. pp
  end
  if pg and pg ~= "" and mapping.page then
    parts[#parts + 1] = mapping.page .. "=" .. pg
  end
  if #parts == 0 then
    return url
  end
  return url .. sep .. table.concat(parts, "&")
end

-- make_fetch_opts is global: backends/<name>.lua uses it to forward auth.
--
-- Returns a Fetch options table with the correct Authorization header for the
-- target provider, or nil when no Authorization header is present on the
-- incoming request. The raw token value passes through verbatim; only the
-- scheme wrapper changes.
--
-- scheme: "token" | "bearer" | "basic-colon" | "basic"
--   "token"       → Authorization: token <tok>
--   "bearer"      → Authorization: Bearer <tok>
--   "basic-colon" → Authorization: Basic base64(:tok)  (Azure DevOps — empty username)
--   "basic"       → Authorization: Basic base64(tok)   (client passes user:pass as tok)
function make_fetch_opts(scheme)
  local h = GetHeader("Authorization")
  if not h or h == "" then
    return nil
  end
  local tok = h:match("^[Tt]oken%s+(.+)$") or h:match("^[Bb]earer%s+(.+)$") or h
  local hdr
  if scheme == "token" then
    hdr = "token " .. tok
  elseif scheme == "bearer" then
    hdr = "Bearer " .. tok
  elseif scheme == "basic-colon" then
    hdr = "Basic " .. EncodeBase64(":" .. tok)
  elseif scheme == "basic" then
    hdr = "Basic " .. EncodeBase64(tok)
  end
  return { headers = { ["Authorization"] = hdr } }
end

-- make_proxy_handler is global: returns a proxy_handler bound to a backend's fetch_json.
-- Each backend calls: local proxy_handler = make_proxy_handler(fetch_json)
--
-- The returned proxy_handler(xform, url_fn) builds a handler function that fetches
-- url_fn(...) and passes the decoded response through xform (plus handler args).
-- xform receives (response_body, ...handler_args) so closures over handler args are not
-- needed. Named translate functions that only take the response body work as-is
-- (extra args are silently ignored by Lua).
-- proxy_fn defaults to proxy_json; pass proxy_json_created for 201 Created endpoints.
function make_proxy_handler(fetch_fn, proxy_fn)
  proxy_fn = proxy_fn or proxy_json
  return function(xform, url_fn)
    return function(...)
      local args = { ... }
      proxy_fn(type(xform) == "function" and function(r)
        return xform(r, table.unpack(args))
      end or xform, fetch_fn(url_fn(...)))
    end
  end
end

local function copy_opts(opts)
  if not opts then
    return nil
  end
  local out = {}
  for k, v in pairs(opts) do
    out[k] = v
  end
  if opts.headers then
    out.headers = {}
    for k, v in pairs(opts.headers) do
      out.headers[k] = v
    end
  end
  return out
end

local function normalize_fetch_opts(method, body, opts)
  opts = copy_opts(opts)
  if method ~= nil and method ~= "GET" then
    opts = opts or {}
    opts.method = method
    if body then
      opts.body = body
      opts.headers = opts.headers or {}
      opts.headers["Content-Type"] = "application/json"
    end
  end
  return opts
end

local function decode_json_body(body)
  return DecodeJson(body) or {}
end

local function proxy_json_with_error(map_error)
  return function(translate, ok, status, _headers, body)
    if ok and status == 200 then
      local data = decode_json_body(body)
      respond_json(200, translate and translate(data) or data)
    elseif ok then
      respond_json(status, map_error(status, body))
    else
      respond_json(503, {})
    end
  end
end

local function proxy_json_created_with_error(map_error)
  return function(translate, ok, status, _headers, body)
    if ok and (status == 200 or status == 201) then
      local data = decode_json_body(body)
      respond_json(201, translate and translate(data) or data)
    elseif ok then
      respond_json(status, map_error(status, body))
    else
      respond_json(503, {})
    end
  end
end

local function proxy_json_paged_with_error(page_params, map_error)
  return function(translate, ok, status, headers, body)
    if ok and status == 200 then
      local data = decode_json_body(body)
      local link = headers and (headers["Link"] or headers["link"])
      local rewritten = rewrite_link_header(link, page_params)
      set_preamble(200)
      if rewritten then
        SetHeader("Link", rewritten)
      end
      Write(EncodeJson(translate and translate(data) or data))
    elseif ok then
      respond_json(status, map_error(status, body))
    else
      respond_json(503, {})
    end
  end
end

local function default_error_shape(_status, _body)
  return {}
end

local function transport_layer(parent, fields)
  return setmetatable(fields or {}, { __index = parent })
end

local function transport_scaffold(fetch_json, fields)
  fields = fields or {}
  fields.fetch_json = fetch_json
  fields.fetch_decoded_json = function(url, method, body)
    local ok, status, headers, raw = fetch_json(url, method, body)
    return ok, status, headers, ok and decode_json_body(raw) or nil, raw
  end
  fields.proxy_handler = make_proxy_handler(fetch_json)
  fields.proxy_handler_created = make_proxy_handler(fetch_json, proxy_json_created)
  return fields
end

-- base_transport is global: the root transport layer. It owns the low-level Fetch
-- call, JSON decoding, method/body option shaping, and default proxy helpers.
base_transport = transport_scaffold(function(url, method, body, opts)
  return pcall(Fetch, url, normalize_fetch_opts(method, body, opts))
end, {
  decode_json = decode_json_body,
  map_error = default_error_shape,
})

-- with_auth is global: returns a transport layer that forwards the inbound
-- Authorization header using the provider's auth scheme.
function with_auth(scheme, parent)
  parent = parent or base_transport
  return transport_layer(
    parent,
    transport_scaffold(function(url, method, body)
      return parent.fetch_json(url, method, body, make_fetch_opts(scheme))
    end)
  )
end

-- with_pagination is global: returns a transport layer with paged proxy helpers.
function with_pagination(pages, parent)
  parent = parent or base_transport
  if not pages then
    return parent
  end
  return transport_layer(parent, {
    page_params = pages,
    proxy_handler_paged = make_proxy_handler(
      parent.fetch_json,
      function(translate, ok, status, headers, body)
        proxy_json_paged(translate, pages, ok, status, headers, body)
      end
    ),
  })
end

-- with_error_shape is global: returns a transport layer whose proxy helpers map
-- non-2xx provider response bodies to GitHub-shaped error bodies.
function with_error_shape(map_error, parent)
  parent = parent or base_transport
  map_error = map_error or default_error_shape
  local fields = {
    map_error = map_error,
    proxy_handler = make_proxy_handler(parent.fetch_json, proxy_json_with_error(map_error)),
    proxy_handler_created = make_proxy_handler(
      parent.fetch_json,
      proxy_json_created_with_error(map_error)
    ),
  }
  if parent.page_params then
    fields.proxy_handler_paged = make_proxy_handler(
      parent.fetch_json,
      proxy_json_paged_with_error(parent.page_params, map_error)
    )
  end
  return transport_layer(parent, fields)
end

-- make_backend_transport is global: builds the standard transport scaffolding for a backend.
--
-- Returns a table with:
--   fetch_json(url[, method[, body]])  — authorized fetch; adds method + Content-Type for
--                                        non-GET calls with a body
--   proxy_handler                       — make_proxy_handler(fetch_json) using proxy_json
--   proxy_handler_created               — make_proxy_handler(fetch_json, proxy_json_created)
--   proxy_handler_paged                 — make_proxy_handler bound to proxy_json_paged with
--                                         the given pages mapping; nil when pages is omitted
--
-- scheme: "token" | "bearer" | "basic" | "basic-colon"  (forwarded to make_fetch_opts)
-- pages:  { per_page = "upstream_name" [, page = "upstream_name"] } for paged endpoints;
--         omit (or pass nil) when the backend has no paged handler.
function make_backend_transport(scheme, pages)
  return with_pagination(pages, with_auth(scheme, base_transport))
end
