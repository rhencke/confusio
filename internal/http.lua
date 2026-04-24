-- HTTP response primitives (global: backends/<name>.lua uses them).
--
-- set_preamble  — set HTTP status and Content-Type before writing a response
-- respond_json  — set_preamble + EncodeJson + Write in one call

local HTTP_STATUS_TEXT = {
  [200] = "OK",
  [201] = "Created",
  [204] = "No Content",
  [302] = "Found",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [409] = "Conflict",
  [410] = "Gone",
  [418] = "I'm a Teapot",
  [422] = "Unprocessable Entity",
  [501] = "Not Implemented",
  [503] = "Service Unavailable",
}

-- set_preamble is global: backends/<name>.lua uses it.
-- Sets the HTTP status (with text looked up by code) and Content-Type header.
-- content_type defaults to "application/json; charset=utf-8".
function set_preamble(status, content_type) -- luacheck: globals set_preamble
  if type(status) == "string" then
    content_type = status
    status = 200
  else
    status = status or 200
  end
  SetStatus(status, HTTP_STATUS_TEXT[status] or tostring(status))
  SetHeader("Content-Type", content_type or "application/json; charset=utf-8")
end

-- respond_json is global: backends/<name>.lua uses it.
function respond_json(status, body) -- luacheck: globals respond_json
  set_preamble(status)
  Write(EncodeJson(body))
end
