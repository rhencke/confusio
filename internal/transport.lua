-- Transport helpers (global: backends/<name>.lua uses them).
--
-- append_page_params     — append translated pagination params to an upstream URL
-- make_fetch_opts        — build a Fetch options table forwarding the caller's auth header
-- make_proxy_handler     — factory: bind a fetch_json function to a proxy response helper
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
  local function fetch_json(url, method, body)
    local opts = make_fetch_opts(scheme)
    if method ~= nil and method ~= "GET" then
      opts = opts or {}
      opts.method = method
      if body then
        opts.body = body
        opts.headers = opts.headers or {}
        opts.headers["Content-Type"] = "application/json"
      end
    end
    return pcall(Fetch, url, opts)
  end
  local proxy_handler_paged
  if pages then
    proxy_handler_paged = make_proxy_handler(
      fetch_json,
      function(translate, ok, status, headers, body)
        proxy_json_paged(translate, pages, ok, status, headers, body)
      end
    )
  end
  return {
    fetch_json = fetch_json,
    proxy_handler = make_proxy_handler(fetch_json),
    proxy_handler_created = make_proxy_handler(fetch_json, proxy_json_created),
    proxy_handler_paged = proxy_handler_paged,
  }
end
