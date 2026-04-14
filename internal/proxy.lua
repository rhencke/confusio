-- Proxy response helpers (global: backends/<name>.lua uses them).
--
-- Helpers for forwarding upstream API responses to the GitHub-shaped caller:
--   rewrite_link_header   — rewrite an upstream Link header to point at confusio
--   proxy_json            — forward a JSON object response (200 passthrough)
--   proxy_json_paged      — like proxy_json but rewrites the Link pagination header
--   proxy_json_created    — forward a create response as 201 Created
--   proxy_health_check    — forward a health probe as 200 {} / 503 {}
--   proxy_204             — forward a mutation response as 204 No Content
--   proxy_json_list       — forward a JSON array response
--   translate_list        — map a function over an array
--   proxy_search_envelope — emit the GitHub search-result envelope

-- rewrite_link_header is global: called by proxy_json_paged.
-- Rewrites each URL in an upstream Link header to point back at confusio.
--
-- upstream_link: raw Link header value from the upstream response (may be nil)
-- mapping: same { per_page = "upstream_name", page = "upstream_name" } as append_page_params
--
-- Returns a GitHub-style Link header value, or nil when there is nothing to emit.
-- Only params present in the reverse mapping survive; unrecognised upstream params are dropped.
function rewrite_link_header(upstream_link, mapping)
  if not upstream_link or upstream_link == "" then
    return nil
  end

  -- Reverse the caller-supplied mapping so we can translate upstream → GitHub param names.
  local reverse = {}
  for gh, up in pairs(mapping) do
    reverse[up] = gh
  end

  local host = GetHeader("Host") or "localhost"
  local proto = GetHeader("X-Forwarded-Proto") or "http"
  local self_base = proto .. "://" .. host .. GetPath()

  local entries = {}
  for url, rel in upstream_link:gmatch('<([^>]+)>%s*;%s*rel="([^"]+)"') do
    local query = url:match("%?(.+)$") or ""
    local params = {}
    for k, v in query:gmatch("([^&=]+)=([^&]+)") do
      local gh = reverse[k]
      if gh then
        params[#params + 1] = gh .. "=" .. v
      end
    end
    local new_url = self_base
    if #params > 0 then
      new_url = new_url .. "?" .. table.concat(params, "&")
    end
    entries[#entries + 1] = "<" .. new_url .. '>; rel="' .. rel .. '"'
  end

  return #entries > 0 and table.concat(entries, ", ") or nil
end

-- proxy_json and proxy_json_created are globals: backends/<name>.lua uses them
-- as the standard upstream-proxy response pattern.
--
-- translate: optional function applied to the decoded response body on success
-- ok, status, headers, body: the four return values from pcall(Fetch,...) or fetch_json(...)
--
-- translate is first so that fetch_json(...) can be the last argument and Lua
-- expands its multiple return values correctly into ok/status/headers/body:
--   proxy_json(translate_fn, fetch_json(url))
--   proxy_json(nil, fetch_json(url))   -- passthrough, no translation
--
-- No Link header is emitted; use proxy_json_paged for paginated list endpoints.
function proxy_json(translate, ok, status, _headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    respond_json(200, translate and translate(data) or data)
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- proxy_json_paged: like proxy_json but rewrites the upstream Link header to point at confusio.
-- page_params sits before the fetch result so fetch_json(...) can still be the last argument
-- and Lua expands its multiple return values correctly:
--   proxy_json_paged(translate_fn, PAGES, fetch_json(url))
--   proxy_json_paged(nil,           PAGES, fetch_json(url))
function proxy_json_paged(translate, page_params, ok, status, headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    local link = headers and (headers["Link"] or headers["link"])
    local rewritten = rewrite_link_header(link, page_params)
    -- set_preamble calls SetStatus which clears previously-set headers, so the Link
    -- header must be set AFTER set_preamble, not before.
    set_preamble(200)
    if rewritten then
      SetHeader("Link", rewritten)
    end
    Write(EncodeJson(translate and translate(data) or data))
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- Like proxy_json but for create endpoints: upstream may return 200 or 201;
-- confusio always responds 201 Created.
function proxy_json_created(translate, ok, status, _headers, body)
  if ok and (status == 200 or status == 201) then
    local data = DecodeJson(body) or {}
    respond_json(201, translate and translate(data) or data)
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- proxy_health_check is global: backends use it to implement get_root.
-- Probes an upstream endpoint; responds 200 {} on success, 503 {} otherwise.
-- Accepts the first two return values of pcall(Fetch, url, opts):
--   proxy_health_check(pcall(Fetch, url, opts))
function proxy_health_check(ok, status)
  if ok and status == 200 then
    respond_json(200, {})
  else
    respond_json(503, {})
  end
end

-- proxy_204 is global: standard mutation/DELETE response helper.
-- Responds 204 No Content if the upstream status is 204 or any status in also_ok.
-- Forwards any other upstream status as-is; responds 503 on connection failure.
--
-- also_ok: nil for 204-only, or a list of additional accepted success statuses.
-- Designed to receive the return values of pcall(Fetch,...) or fetch_json(...):
--   proxy_204(nil, pcall(Fetch, url, opts))          -- 204-only
--   proxy_204({200}, fetch_json(url, "DELETE"))      -- also accept 200
--   proxy_204({202}, pcall(Fetch, url, opts))        -- also accept 202
--   proxy_204({200, 201}, pcall(Fetch, url, opts))   -- also accept 200 or 201
function proxy_204(also_ok, ok, status)
  local success = status == 204
  if not success and also_ok then
    for _, s in ipairs(also_ok) do
      if s == status then
        success = true
        break
      end
    end
  end
  if ok and success then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- proxy_json_list is global: standard list-endpoint response helper.
-- Translates a successful 200 upstream array response to a JSON array,
-- writing "[]" rather than "{}" when the result is empty.
-- translate receives the decoded array and returns the translated array.
-- Designed to receive the return values of fetch_json(...):
--   proxy_json_list(translate, fetch_json(url))
function proxy_json_list(translate, ok, status, _headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    local result = translate(data)
    set_preamble()
    Write(#result > 0 and EncodeJson(result) or "[]")
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- translate_list is global: apply fn to each element of items and return a new array.
-- Replaces the repeated for-i-ipairs + arr[i]=fn(item) pattern in backend modules.
--   translate_list(translate_item, data.values)
--   translate_list(translate_item, data)
function translate_list(fn, items)
  local result = {}
  for i, item in ipairs(items or {}) do
    result[i] = fn(item)
  end
  return result
end

-- proxy_search_envelope is global: emit the GitHub search response envelope.
-- translate_item: applied to each element of the upstream array.
-- container: nil = use the decoded body itself as the array;
--            string = use body[container] as the array (e.g. "values", "data").
-- Designed to receive the return values of fetch_json(...):
--   proxy_search_envelope(translate_fn, "values", fetch_json(url))
--   proxy_search_envelope(translate_fn, "data",   fetch_json(url))
--   proxy_search_envelope(translate_fn, nil,      fetch_json(url))
function proxy_search_envelope(translate_item, container, ok, status, _headers, body)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local raw = DecodeJson(body) or {}
  local src = type(container) == "string" and (raw[container] or {}) or raw
  local items = translate_list(translate_item, src)
  set_preamble()
  Write(
    '{"total_count":'
      .. #items
      .. ',"incomplete_results":false,"items":'
      .. (#items > 0 and EncodeJson(items) or "[]")
      .. "}"
  )
end
